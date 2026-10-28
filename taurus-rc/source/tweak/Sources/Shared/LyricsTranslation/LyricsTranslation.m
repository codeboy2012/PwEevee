#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Headers/SPTPlayer.h"
#import "LyricsTranslation.h"

// gemini-flash-latest follows each Flash release; Google gives two weeks' notice of a breaking change.
static NSString *const kEndpoint = @"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent";
static NSString *const kService = @"PwEevee.Gemini", *const kAccount = @"api-key";
// The keychain service the pre-rename builds stored their key under; read once to migrate.
static NSString *const kLegacyService = @"Taurus.Gemini";

#pragma mark - the key

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}

static NSDictionary *legacyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kLegacyService, (__bridge id)kSecAttrAccount: kAccount};
}

static NSString *keyIn(NSDictionary *query) {
    NSMutableDictionary *ask = [query mutableCopy];
    ask[(__bridge id)kSecReturnData] = @YES;
    ask[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)ask, &data) != errSecSuccess || !data) return nil;
    NSString *key = [[NSString alloc] initWithData:(__bridge_transfer NSData *)data encoding:NSUTF8StringEncoding];
    return key.length ? key : nil;
}

static void storeKey(NSString *key) {
    SecItemDelete((__bridge CFDictionaryRef)keyQuery());
    if (!key.length) return;
    NSMutableDictionary *item = [keyQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status != errSecSuccess) SGLog(@"gemini: the key could not be kept (%d)", (int)status);
}

// One-time migration: a key kept under the pre-rename service is copied across; the legacy item is
// deleted only after the new item read back the same value, so an upgrade keeps its key.
static NSString *storedKey(void) {
    NSString *key = keyIn(keyQuery());
    if (key) return key;
    NSString *legacy = keyIn(legacyQuery());
    if (!legacy) return nil;
    storeKey(legacy);
    NSString *migrated = keyIn(keyQuery());
    if ([migrated isEqualToString:legacy]) SecItemDelete((__bridge CFDictionaryRef)legacyQuery());
    SGLog(@"gemini: the key moved to its new keychain place");
    return migrated ?: legacy;
}

BOOL SGGeminiKeySet(void) {
    return storedKey() != nil;
}

#pragma mark - asking

NSString *SGLyricsSongName(NSString *trackID) {
    NSDictionary *local = trackID ? SGLocalFileInfo(trackID) : nil;
    SPTPlayerTrack *track = trackID && !local ? SGKaraokeTrackFor(trackID) : nil;
    NSString *title = local ? local[@"title"] : track.trackTitle, *artist = local ? local[@"artist"] : track.artistName;
    if (![title isKindOfClass:NSString.class] || !title.length) return nil;
    return [artist isKindOfClass:NSString.class] && artist.length ? [NSString stringWithFormat:@"\u201C%@\u201D by %@", title, artist]
                                                                     : [NSString stringWithFormat:@"\u201C%@\u201D", title];
}

NSString *SGLyricsGeminiLanguage(void) {
    return SGLyricsTranslationLanguage() ?: NSLocale.preferredLanguages.firstObject ?: @"en";
}

// Why Gemini stopped short, as finishReason or promptFeedback.blockReason name it.
static NSString *blockedBecause(NSString *reason) {
    if ([reason isEqualToString:@"RECITATION"]) return @"Gemini stopped because its answer repeated published lyrics.";
    if ([@[@"SAFETY", @"PROHIBITED_CONTENT", @"BLOCKLIST", @"SPII"] containsObject:reason]) return @"Gemini's filters blocked this song's lyrics.";
    if ([reason isEqualToString:@"MAX_TOKENS"]) return @"The song is too long for one answer from Gemini.";
    return [NSString stringWithFormat:@"Gemini stopped before translating the song (%@).", reason];
}

NSArray<NSString *> *SGGeminiTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem) {
    NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
    id candidates = reply[@"candidates"];
    id first = [candidates isKindOfClass:NSArray.class] ? [candidates firstObject] : nil;
    id parts = [first isKindOfClass:NSDictionary.class] && [first[@"content"] isKindOfClass:NSDictionary.class] ? first[@"content"][@"parts"] : nil;
    id text = [parts isKindOfClass:NSArray.class] && [[parts firstObject] isKindOfClass:NSDictionary.class] ? [parts firstObject][@"text"] : nil;
    id parsed = [text isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    if ([parsed isKindOfClass:NSArray.class] && [parsed count] == count) {
        NSMutableArray<NSString *> *clean = [NSMutableArray arrayWithCapacity:count];
        for (id line in parsed) [clean addObject:[line isKindOfClass:NSString.class] ? line : @""];
        return clean;
    }
    id feedback = reply[@"promptFeedback"];
    id blocked = [feedback isKindOfClass:NSDictionary.class] ? feedback[@"blockReason"] : nil;
    id finished = [first isKindOfClass:NSDictionary.class] ? first[@"finishReason"] : nil;
    id failed = [reply[@"error"] isKindOfClass:NSDictionary.class] ? reply[@"error"][@"message"] : nil;
    NSString *googleSays = [failed isKindOfClass:NSString.class] ? failed : nil;
    if (error) {
        *problem = @"Gemini could not be reached.";
    } else if (status == 401 || status == 403 || (status == 400 && [googleSays localizedCaseInsensitiveContainsString:@"API key"])) {
        *problem = @"Gemini turned the key down. Check it on the Lyrics page.";
    } else if (status == 400) {
        *problem = googleSays.length ? [NSString stringWithFormat:@"Gemini did not take the request: %@", googleSays]
                                     : @"Gemini did not take the request (400).";
    } else if (status == 429) {
        *problem = @"Gemini's limit for this key is reached for now.";
    } else if (status == 503 || status == 500) {
        *problem = @"Gemini is busy right now. Try again in a minute.";
    } else if (status != 200) {
        *problem = [NSString stringWithFormat:@"Gemini did not translate the song (%ld).", (long)status];
    } else if ([blocked isKindOfClass:NSString.class]) {
        *problem = blockedBecause(blocked);
    } else if ([finished isKindOfClass:NSString.class] && ![finished isEqualToString:@"STOP"]) {
        *problem = blockedBecause(finished);
    } else if ([parsed isKindOfClass:NSArray.class]) {
        *problem = [NSString stringWithFormat:@"Gemini answered %lu lines for the song's %lu. Try again.",
                    (unsigned long)[parsed count], (unsigned long)count];
    } else {
        *problem = @"Gemini's answer could not be read. Try again.";
    }
    return nil;
}

// Google's advice for a busy model or a full minute's quota (408, 429, 5xx): ask again after about 1, 2 and 4 s,
// spread a little so phones do not all come back at once. A key turned down or a request that timed out is not
// asked again.
// plain is the same request without the thinking level, sent once if Gemini turns that field down: a model behind
// gemini-flash-latest that does not know it still translates.
static void sendToGemini(NSURLRequest *request, NSURLRequest *plain, NSUInteger attempt,
                         void (^finished)(NSData *data, NSInteger status, NSError *error)) {
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *reply = status == 400 && data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (plain && [reply localizedCaseInsensitiveContainsString:@"thinking"]) {
            SGLog(@"gemini: the thinking level was turned down, asking without it");
            sendToGemini(plain, nil, attempt, finished);
            return;
        }
        if (attempt < 3 && !error && (status == 408 || status == 429 || status >= 500)) {
            double delay = (double)(1 << attempt) * (0.75 + arc4random_uniform(500) / 1000.0);
            SGLog(@"gemini: %ld, asking again in %.1f s", (long)status, delay);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                sendToGemini(request, plain, attempt + 1, finished);
            });
            return;
        }
        finished(data, status, error);
    }] resume];
}

static NSMutableDictionary<NSString *, NSArray<NSString *> *> *sg_done;   // per launch, by track and language

void SGLyricsTranslateWithGemini(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *translations, NSString *error)) {
    NSString *key = storedKey();
    if (!key) {
        done(nil, @"Add a Gemini API key on the Lyrics page first.");
        return;
    }
    if (!sg_done) sg_done = [NSMutableDictionary dictionary];
    NSString *memo = [NSString stringWithFormat:@"%@|%@", trackID, languageTag];
    if (trackID && sg_done[memo].count == lines.count) {
        done(sg_done[memo], nil);
        return;
    }
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:SGKaraokeLineText(line) ?: @""];
    // By the whole tag, so the script stays: zh-Hant is "Chinese, Traditional" where its language alone is "Chinese".
    NSString *language = [[NSLocale localeWithLocaleIdentifier:@"en"] localizedStringForLocaleIdentifier:languageTag] ?: languageTag;
    NSData *input = [NSJSONSerialization dataWithJSONObject:texts options:0 error:nil];
    NSString *prompt = [NSString stringWithFormat:
        @"Translate the lines of this song into %@. Answer with a JSON array of exactly %lu strings, one "
        @"per input line and in the same order. Translate the meaning naturally, keep each line short like a "
        @"lyric, and keep an empty line empty. A line already in %@ stays as it is.\n\n%@",
        language, (unsigned long)texts.count, language, [[NSString alloc] initWithData:input encoding:NSUTF8StringEncoding]];
    // Lyrics are often explicit, and translating them is what the user asked for, so every filter that can
    // be lowered is. Recitation cannot be switched off, and is named when it stops an answer.
    NSMutableArray *safety = [NSMutableArray array];
    for (NSString *category in @[@"HARM_CATEGORY_HARASSMENT", @"HARM_CATEGORY_HATE_SPEECH",
                                 @"HARM_CATEGORY_SEXUALLY_EXPLICIT", @"HARM_CATEGORY_DANGEROUS_CONTENT"]) {
        [safety addObject:@{@"category": category, @"threshold": @"BLOCK_NONE"}];
    }
    NSDictionary *body = @{
        @"contents": @[@{@"parts": @[@{@"text": prompt}]}],
        @"safetySettings": safety,
        @"generationConfig": @{
            @"responseMimeType": @"application/json",
            @"responseSchema": @{@"type": @"ARRAY", @"items": @{@"type": @"STRING"}},
            // Gemini 3 thinks at length by default, which a whole song's translation does not need and which
            // made it slow enough to time out.
            @"thinkingConfig": @{@"thinkingLevel": @"low"},
        },
    };
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kEndpoint]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *plain = [request mutableCopy];
    NSMutableDictionary *plainBody = [body mutableCopy], *plainConfig = [body[@"generationConfig"] mutableCopy];
    [plainConfig removeObjectForKey:@"thinkingConfig"];
    plainBody[@"generationConfig"] = plainConfig;
    plain.HTTPBody = [NSJSONSerialization dataWithJSONObject:plainBody options:0 error:nil];
    sendToGemini(request, plain, 0, ^(NSData *data, NSInteger status, NSError *error) {
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *problem = nil;
        NSArray *translations = SGGeminiTranslationsIn(root, status, error, texts.count, &problem);
        SGLog(@"gemini: %@ lines into %@: %@", @(texts.count), languageTag, translations ? @"translated" : problem);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (translations && trackID) sg_done[memo] = translations;
            done(translations, problem);
        });
    });
}

#pragma mark - the row

static void askForKey(void) {
    // Says what leaves the phone, not only where the key stays: each song translated goes to Google whole.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gemini API key"
        message:@"Translate with Gemini sends the song's lyrics to Google, on your own key from Google AI Studio. The key stays on this iPhone."
        preferredStyle:UIAlertControllerStyleAlert];
    // An empty field would store nothing and take the key away, which only Remove is for: Save waits for text.
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // A key copied with the quotes around it, as from a code sample, is turned down by Google as it stands.
        NSMutableCharacterSet *around = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [around addCharactersInString:@"\"'“”‘’"];
        NSString *key = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:around];
        if (key.length) storeKey(key);
    }];
    save.enabled = NO;
    __weak UIAlertAction *weakSave = save;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"API key";
        field.secureTextEntry = YES;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        __weak UITextField *weakField = field;   // the field keeps its actions, and the alert both
        [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
            weakSave.enabled = [weakField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
        }] forControlEvents:UIControlEventEditingChanged];
    }];
    [alert addAction:save];
    if (SGGeminiKeySet()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            storeKey(nil);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"spotifyglass.lyricsTranslationsDidChange";

SGModRow *SGTranslateEverySongRow(void) {
    SGModRow *row = SGOptionRow(@"Translate any song", @"The lyrics' translate menu for songs that already read as your language",
                                SGKeyLyricsTranslateEverySong);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGGeminiKeyRow(void) {
    return SGStatActionRow(@"Gemini API key", @"Translate any song from the lyrics' corner menu",
                           ^NSString *{ return SGGeminiKeySet() ? @"Set" : @"Off"; }, ^{ askForKey(); });
}
