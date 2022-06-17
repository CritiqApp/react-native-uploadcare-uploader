#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(UploadcareUploader, NSObject)

RCT_EXTERN_METHOD(upload:(NSString*)key filePath:(NSString*)path mimeType:(NSString*)type
                 progressCallback:(RCTResponseSenderBlock *)progress
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

@end
