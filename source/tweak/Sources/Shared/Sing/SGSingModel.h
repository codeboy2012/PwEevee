#import <Foundation/Foundation.h>

#define SGKeySingModelDownload @"spotifyglass.sing.modelDownload"
#define SGKeySingModel @"spotifyglass.sing.model"

typedef NS_ENUM(NSInteger, SGSingModelKind) {
    SGSingModelFull,
    SGSingModelLight,
};

typedef NS_ENUM(NSInteger, SGSingModelState) {
    SGSingModelMissing,       // not on this iPhone; SGSingModelReceived says how much a stopped download kept
    SGSingModelDownloading,   // files coming in, or waiting for a network to come in on
    SGSingModelChecking,      // everything is in, the last files are being checked
    SGSingModelInstalled,     // checked and in place
};

// Posted as the state or the progress changes, the progress at most four times a second.
extern NSNotificationName const SGSingModelDidChangeNotification;
extern NSString *const SGSingModelDidChangeChoiceKey;

SGSingModelState SGSingModelCurrentState(void);
SGSingModelKind SGSingModelChosen(void);
void SGSingModelChoose(SGSingModelKind kind);
int64_t SGSingModelSize(void);       // all of it, as pinned
NSString *SGSingModelSizeTextOf(SGSingModelKind kind);
int64_t SGSingModelReceived(void);   // what of it is on this iPhone, checked or not
NSString *SGSingModelFailure(void);  // why the last download stopped short, nil unless it did
NSString *SGSingModelPath(void);     // the selected installed separator, nil without one
NSString *SGSingModelBytesText(int64_t bytes);   // rounded MiB, in the units the rows use

// What keeps a download from starting: too little free space, said with how much it needs. Nil when none.
NSString *SGSingModelSpaceProblem(void);

typedef NS_ENUM(NSInteger, SGSingModelNetwork) {
    SGSingModelOffline,
    SGSingModelUnmetered,   // Wi-Fi or wired
    SGSingModelMetered,     // cellular, a personal hotspot or Low Data Mode
};
// The network the phone is on now, asked once; `done` runs on the main queue.
void SGSingModelCheckNetwork(void (^done)(SGSingModelNetwork network));

void SGSingModelDownload(BOOL metered);
void SGSingModelCancel(void);   // keeps what came in, for the next Download
void SGSingModelRemove(void);   // the model and anything half downloaded

BOOL SGSingModelHandlesSession(NSString *identifier, void (^completion)(void));
void SGSingModelReconnect(void);
