// Where a track's Canvas comes from, as plain data: the hook tests these without the app around them.
#import <Foundation/Foundation.h>

@interface SGCanvas : NSObject
@property (nonatomic, copy) NSString *identifier;   // canvas.id, the file id where there is none
@property (nonatomic, copy) NSString *address;      // the clip's URL
@property (nonatomic) BOOL video;                   // an IMAGE or GIF canvas is not one of ours
@end

SGCanvas *SGCanvasFromMetadata(NSDictionary *metadata);

NSData *SGCanvazRequestBody(NSString *trackURI);
SGCanvas *SGCanvazFromBody(NSData *body);
