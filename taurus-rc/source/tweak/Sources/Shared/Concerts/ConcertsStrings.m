// The three phrases of the concerts card in every language Spotify's settings offer, picked by the language
// the app runs in (the per-app language of iOS, else the system's). A language with no row here reads in
// English. Order of each row: Upcoming Concerts, Concerts, Tickets.
#import "Concerts.h"

static NSDictionary<NSString *, NSArray<NSString *> *> *table(void) {
    static NSDictionary *strings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        strings = @{
            @"en": @[@"Upcoming Concerts", @"Concerts", @"Tickets"],
            @"af": @[@"Komende konserte", @"Konserte", @"Kaartjies"],
            @"am": @[@"ቀጣይ ኮንሰርቶች", @"ኮንሰርቶች", @"ቲኬቶች"],
            @"ar": @[@"الحفلات القادمة", @"الحفلات", @"التذاكر"],
            @"az": @[@"Gələn konsertlər", @"Konsertlər", @"Biletlər"],
            @"bg": @[@"Предстоящи концерти", @"Концерти", @"Билети"],
            @"bn": @[@"আসন্ন কনসার্ট", @"কনসার্ট", @"টিকিট"],
            @"bs": @[@"Nadolazeći koncerti", @"Koncerti", @"Ulaznice"],
            @"ca": @[@"Propers concerts", @"Concerts", @"Entrades"],
            @"cs": @[@"Nadcházející koncerty", @"Koncerty", @"Vstupenky"],
            @"da": @[@"Kommende koncerter", @"Koncerter", @"Billetter"],
            @"de": @[@"Kommende Konzerte", @"Konzerte", @"Tickets"],
            @"el": @[@"Επερχόμενες συναυλίες", @"Συναυλίες", @"Εισιτήρια"],
            @"es": @[@"Próximos conciertos", @"Conciertos", @"Entradas"],
            @"es-419": @[@"Próximos conciertos", @"Conciertos", @"Boletos"],
            @"et": @[@"Tulevased kontserdid", @"Kontserdid", @"Piletid"],
            @"eu": @[@"Hurrengo kontzertuak", @"Kontzertuak", @"Sarrerak"],
            @"fa": @[@"کنسرت‌های پیش رو", @"کنسرت‌ها", @"بلیت‌ها"],
            @"fi": @[@"Tulevat konsertit", @"Konsertit", @"Liput"],
            @"fil": @[@"Mga Paparating na Konsiyerto", @"Mga Konsiyerto", @"Mga Tiket"],
            @"fr": @[@"Prochains concerts", @"Concerts", @"Billets"],
            @"gl": @[@"Próximos concertos", @"Concertos", @"Entradas"],
            @"gu": @[@"આગામી કોન્સર્ટ", @"કોન્સર્ટ", @"ટિકિટ"],
            @"he": @[@"הופעות קרובות", @"הופעות", @"כרטיסים"],
            @"hi": @[@"आगामी कॉन्सर्ट", @"कॉन्सर्ट", @"टिकट"],
            @"hr": @[@"Nadolazeći koncerti", @"Koncerti", @"Ulaznice"],
            @"hu": @[@"Közelgő koncertek", @"Koncertek", @"Jegyek"],
            @"hy": @[@"Առաջիկա համերգներ", @"Համերգներ", @"Տոմսեր"],
            @"id": @[@"Konser Mendatang", @"Konser", @"Tiket"],
            @"is": @[@"Væntanlegir tónleikar", @"Tónleikar", @"Miðar"],
            @"it": @[@"Prossimi concerti", @"Concerti", @"Biglietti"],
            @"ja": @[@"今後のコンサート", @"コンサート", @"チケット"],
            @"ka": @[@"მომავალი კონცერტები", @"კონცერტები", @"ბილეთები"],
            @"kk": @[@"Алдағы концерттер", @"Концерттер", @"Билеттер"],
            @"kn": @[@"ಮುಂಬರುವ ಕಾನ್ಸರ್ಟ್‌ಗಳು", @"ಕಾನ್ಸರ್ಟ್‌ಗಳು", @"ಟಿಕೆಟ್‌ಗಳು"],
            @"ko": @[@"예정된 콘서트", @"콘서트", @"티켓"],
            @"lt": @[@"Būsimi koncertai", @"Koncertai", @"Bilietai"],
            @"lv": @[@"Gaidāmie koncerti", @"Koncerti", @"Biļetes"],
            @"mk": @[@"Претстојни концерти", @"Концерти", @"Билети"],
            @"ml": @[@"വരാനിരിക്കുന്ന കച്ചേരികൾ", @"കച്ചേരികൾ", @"ടിക്കറ്റുകൾ"],
            @"mr": @[@"आगामी कॉन्सर्ट", @"कॉन्सर्ट", @"तिकिटे"],
            @"ms": @[@"Konsert Akan Datang", @"Konsert", @"Tiket"],
            @"nb": @[@"Kommende konserter", @"Konserter", @"Billetter"],
            @"ne": @[@"आगामी कन्सर्टहरू", @"कन्सर्टहरू", @"टिकटहरू"],
            @"nl": @[@"Aankomende concerten", @"Concerten", @"Tickets"],
            @"pa": @[@"ਆਉਣ ਵਾਲੇ ਕੰਸਰਟ", @"ਕੰਸਰਟ", @"ਟਿਕਟਾਂ"],
            @"pl": @[@"Nadchodzące koncerty", @"Koncerty", @"Bilety"],
            @"pt": @[@"Próximos shows", @"Shows", @"Ingressos"],
            @"pt-PT": @[@"Próximos concertos", @"Concertos", @"Bilhetes"],
            @"ro": @[@"Concerte viitoare", @"Concerte", @"Bilete"],
            @"ru": @[@"Предстоящие концерты", @"Концерты", @"Билеты"],
            @"si": @[@"ඉදිරි ප්‍රසංග", @"ප්‍රසංග", @"ටිකට්පත්"],
            @"sk": @[@"Nadchádzajúce koncerty", @"Koncerty", @"Vstupenky"],
            @"sl": @[@"Prihajajoči koncerti", @"Koncerti", @"Vstopnice"],
            @"sq": @[@"Koncertet e ardhshme", @"Koncertet", @"Bileta"],
            @"sr": @[@"Предстојећи концерти", @"Концерти", @"Улазнице"],
            @"sr-Latn": @[@"Predstojeći koncerti", @"Koncerti", @"Ulaznice"],
            @"sv": @[@"Kommande konserter", @"Konserter", @"Biljetter"],
            @"sw": @[@"Matamasha yajayo", @"Matamasha", @"Tiketi"],
            @"ta": @[@"வரவிருக்கும் கச்சேரிகள்", @"கச்சேரிகள்", @"டிக்கெட்டுகள்"],
            @"te": @[@"రాబోయే కచేరీలు", @"కచేరీలు", @"టిక్కెట్లు"],
            @"th": @[@"คอนเสิร์ตที่กำลังจะมาถึง", @"คอนเสิร์ต", @"บัตร"],
            @"tr": @[@"Yaklaşan Konserler", @"Konserler", @"Biletler"],
            @"uk": @[@"Майбутні концерти", @"Концерти", @"Квитки"],
            @"ur": @[@"آنے والے کنسرٹس", @"کنسرٹس", @"ٹکٹ"],
            @"uz": @[@"Yaqinlashayotgan konsertlar", @"Konsertlar", @"Chiptalar"],
            @"vi": @[@"Buổi hòa nhạc sắp tới", @"Buổi hòa nhạc", @"Vé"],
            @"zh-Hans": @[@"即将举行的演唱会", @"演唱会", @"门票"],
            @"zh-Hant": @[@"即將舉行的演唱會", @"演唱會", @"票券"],
            @"zh-HK": @[@"即將舉行的演唱會", @"演唱會", @"門票"],
            @"zu": @[@"Imibukiso ezayo", @"Imibukiso", @"Amathikithi"],
        };
    });
    return strings;
}

// "es-MX" and the like, written the way the table keys the Latin American Spanish.
static NSSet<NSString *> *latinAmerica(void) {
    return [NSSet setWithArray:@[@"419", @"MX", @"AR", @"CL", @"CO", @"PE", @"VE", @"EC", @"UY", @"PY", @"BO", @"CR",
                                 @"PA", @"DO", @"GT", @"HN", @"NI", @"SV", @"CU", @"PR", @"US"]];
}

// The keys to try for one language identifier, most specific first: "zh-Hant-TW" is zh-Hant-TW, zh-Hant, zh.
static NSArray<NSString *> *candidates(NSString *identifier) {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:identifier];
    NSString *language = locale.languageCode ?: @"en";
    NSString *script = locale.scriptCode, *region = locale.countryCode;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    if ([language isEqualToString:@"zh"]) {
        BOOL traditional = [script isEqualToString:@"Hant"] || (!script && ([region isEqualToString:@"TW"] || [region isEqualToString:@"HK"] || [region isEqualToString:@"MO"]));
        if ([region isEqualToString:@"HK"] || [region isEqualToString:@"MO"]) [keys addObject:@"zh-HK"];
        [keys addObject:traditional ? @"zh-Hant" : @"zh-Hans"];
        return keys;
    }
    if ([language isEqualToString:@"es"] && region && [latinAmerica() containsObject:region]) [keys addObject:@"es-419"];
    if ([language isEqualToString:@"pt"] && [region isEqualToString:@"PT"]) [keys addObject:@"pt-PT"];
    if ([language isEqualToString:@"sr"] && [script isEqualToString:@"Latn"]) [keys addObject:@"sr-Latn"];
    // Spotify's Norwegian is Bokmål, which iOS names nb or no.
    if ([language isEqualToString:@"no"] || [language isEqualToString:@"nn"]) language = @"nb";
    if ([language isEqualToString:@"tl"]) language = @"fil";
    if ([language isEqualToString:@"iw"]) language = @"he";
    [keys addObject:language];
    return keys;
}

static NSString *languageIdentifier(void) {
    return NSLocale.preferredLanguages.firstObject ?: @"en";
}

NSLocale *SGConcertLocale(void) {
    return [NSLocale localeWithLocaleIdentifier:languageIdentifier()];
}

NSString *SGConcertString(SGConcertText text) {
    for (NSString *key in candidates(languageIdentifier())) {
        NSArray<NSString *> *row = table()[key];
        if (row && text >= 0 && text < (NSInteger)row.count) return row[text];
    }
    return table()[@"en"][text];
}

NSString *SGConcertCountLine(NSUInteger count) {
    NSNumberFormatter *numbers = [NSNumberFormatter new];
    numbers.locale = SGConcertLocale();
    NSString *number = [numbers stringFromNumber:@(count)] ?: @(count).stringValue;
    return [NSString stringWithFormat:@"%@ · %@", SGConcertString(SGConcertTextConcerts), number];
}

NSString *SGConcertFormat(SGConcert *concert, NSString *template) {
    if (!concert.date) return @"";
    static NSMutableDictionary<NSString *, NSDateFormatter *> *formatters;
    NSLocale *locale = SGConcertLocale();
    NSTimeZone *zone = concert.zone ?: NSTimeZone.localTimeZone;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@", template, locale.localeIdentifier, zone.name];
    if (!formatters) formatters = [NSMutableDictionary dictionary];
    NSDateFormatter *formatter = formatters[key];
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = locale;
        formatter.timeZone = zone;
        formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:locale];
        formatters[key] = formatter;
    }
    return [formatter stringFromDate:concert.date];
}
