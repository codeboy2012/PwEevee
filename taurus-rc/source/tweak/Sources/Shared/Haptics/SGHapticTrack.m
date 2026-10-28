// SGHapticTrack.h says what this reads and where its field numbers come from.
#import "SGHapticTrack.h"
#import "Shared/AdBlock/Protobuf.h"

// BatchedEntityRequest.entity_request, EntityRequest.entity_uri and .query, ExtensionQuery.extension_kind.
enum { kRequestEntity = 2, kEntityURI = 1, kEntityQuery = 2, kQueryKind = 1 };
// BatchedExtensionResponse.extended_metadata; EntityExtensionDataArray.header, .extension_kind and
// .extension_data; its header's provider_error_status.
enum { kReplyArrays = 2, kArrayHeader = 1, kArrayKind = 2, kArrayData = 3, kArrayStatus = 1 };
// EntityExtensionData.header, .entity_uri and .extension_data; its header's status_code; Any.type_url and .value.
enum { kDataHeader = 1, kDataURI = 2, kDataAny = 3, kDataStatus = 1, kAnyType = 1, kAnyValue = 2 };
// Track.external_id; ExternalId.type and .id.
enum { kTrackExternalID = 10, kExternalType = 1, kExternalID = 2 };
static const uint64_t kTrackV4 = 10;
static NSString *const kTrackType = @"type.googleapis.com/spotify.metadata.Track";

NSString *SGHapticISRC(NSString *code) {
    if (![code isKindOfClass:NSString.class] || code.length != 12) return nil;
    NSString *upper = code.uppercaseString;
    NSRange whole = [upper rangeOfString:@"^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$" options:NSRegularExpressionSearch];
    return whole.location == NSNotFound ? nil : upper;
}

BOOL SGHapticIsTrackURI(NSString *uri) {
    if (![uri isKindOfClass:NSString.class]) return NO;
    return [uri rangeOfString:@"^spotify:track:[0-9A-Za-z]{22}$" options:NSRegularExpressionSearch].location != NSNotFound;
}

NSData *SGHapticTrackRequest(NSString *trackURI) {
    NSData *query = SGPBSerialize(@[SGPBVarint(kQueryKind, kTrackV4)]);
    NSData *entity = SGPBSerialize(@[SGPBString(kEntityURI, trackURI), SGPBBytes(kEntityQuery, query)]);
    return SGPBSerialize(@[SGPBBytes(kRequestEntity, entity)]);
}

static NSArray<SGPBField *> *allOf(NSArray<SGPBField *> *fields, uint32_t number, uint8_t wire) {
    NSMutableArray<SGPBField *> *found = [NSMutableArray array];
    for (SGPBField *field in fields) {
        if (field.number == number && field.wire == wire) [found addObject:field];
    }
    return found;
}

static NSArray<SGPBField *> *messageIn(NSArray<SGPBField *> *fields, uint32_t number) {
    SGPBField *field = allOf(fields, number, 2).firstObject;
    return field ? SGPBParse(field.payload) : nil;
}

// An explicit status other than 200 is a failure; proto3 leaves a 0 off the wire, so a missing one reads 0.
static uint64_t statusIn(NSArray<SGPBField *> *header, uint32_t number) {
    return allOf(header, number, 0).firstObject.varint;
}

NSString *SGHapticISRCInReply(NSData *reply, NSString *trackURI, BOOL *answered) {
    *answered = NO;
    for (SGPBField *arrayField in allOf(SGPBParse(reply), kReplyArrays, 2)) {
        NSArray<SGPBField *> *array = SGPBParse(arrayField.payload);
        NSArray<SGPBField *> *arrayHeader = messageIn(array, kArrayHeader);
        // A provider's status may be missing, but not other than 200 when it is there.
        if (!array || (allOf(arrayHeader, kArrayStatus, 0).count && statusIn(arrayHeader, kArrayStatus) != 200)) continue;
        SGPBField *kind = allOf(array, kArrayKind, 0).firstObject;
        if (kind && kind.varint != kTrackV4) continue;
        for (SGPBField *dataField in allOf(array, kArrayData, 2)) {
            NSArray<SGPBField *> *data = SGPBParse(dataField.payload);
            if (![SGPBText(allOf(data, kDataURI, 2).firstObject) isEqualToString:trackURI]) continue;
            if (statusIn(messageIn(data, kDataHeader), kDataStatus) != 200) continue;
            NSArray<SGPBField *> *any = messageIn(data, kDataAny);
            if (![SGPBText(allOf(any, kAnyType, 2).firstObject) isEqualToString:kTrackType]) continue;
            SGPBField *value = allOf(any, kAnyValue, 2).firstObject;
            NSArray<SGPBField *> *track = value ? SGPBParse(value.payload) : nil;
            if (!track) continue;
            *answered = YES;
            for (SGPBField *externalField in allOf(track, kTrackExternalID, 2)) {
                NSArray<SGPBField *> *external = SGPBParse(externalField.payload);
                if ([SGPBText(allOf(external, kExternalType, 2).firstObject).lowercaseString isEqualToString:@"isrc"]) {
                    NSString *isrc = SGHapticISRC(SGPBText(allOf(external, kExternalID, 2).firstObject));
                    if (isrc) return isrc;
                }
            }
            return nil;
        }
    }
    return nil;
}

static id valueAt(id dictionary, NSString *key) {
    return [dictionary isKindOfClass:NSDictionary.class] ? dictionary[key] : nil;
}

NSString *SGHapticSongIn(NSArray *songs, NSString *isrc, double ms) {
    NSString *wanted = SGHapticISRC(isrc);
    if (!wanted || ms <= 0 || ![songs isKindOfClass:NSArray.class]) return nil;
    for (id song in songs) {
        id identifier = valueAt(song, @"id"), attributes = valueAt(song, @"attributes");
        id length = valueAt(attributes, @"durationInMillis"), haptics = valueAt(attributes, @"hasHaptics");
        if (![identifier isKindOfClass:NSString.class] || ![identifier length]) continue;
        if (![SGHapticISRC(valueAt(attributes, @"isrc")) isEqualToString:wanted]) continue;
        if (![length isKindOfClass:NSNumber.class] || fabs([length doubleValue] - ms) > kHapticLengthSlack) continue;
        if (![haptics isKindOfClass:NSNumber.class] || ![haptics boolValue]) continue;
        return identifier;
    }
    return nil;
}
