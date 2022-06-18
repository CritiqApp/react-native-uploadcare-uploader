#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(UploadcareUploader, RCTEventEmitter)

RCT_EXTERN_METHOD(upload:(NSString*)key filePath:(NSString*)path mimeType:(NSString*)type metaData:(NSDictionary*)data
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

@end
