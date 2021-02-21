//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppLauncherNoDatabase.h>
#import <EXUpdates/EXUpdatesCrypto.h>
#import <EXUpdates/EXUpdatesFileDownloader.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const EXUpdatesFileDownloaderErrorDomain = @"EXUpdatesFileDownloader";
NSTimeInterval const EXUpdatesDefaultTimeoutInterval = 60;

@interface EXUpdatesFileDownloader () <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (nonatomic, strong) EXUpdatesConfig *config;

@end

@implementation EXUpdatesFileDownloader

- (instancetype)initWithUpdatesConfig:(EXUpdatesConfig *)updatesConfig
{
  return [self initWithUpdatesConfig:updatesConfig
             URLSessionConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
}

- (instancetype)initWithUpdatesConfig:(EXUpdatesConfig *)updatesConfig
              URLSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration
{
  if (self = [super init]) {
    _sessionConfiguration = sessionConfiguration;
    _session = [NSURLSession sessionWithConfiguration:_sessionConfiguration delegate:self delegateQueue:nil];
    _config = updatesConfig;
  }
  return self;
}

- (void)dealloc
{
  [_session finishTasksAndInvalidate];
}

+ (dispatch_queue_t)assetFilesQueue
{
  static dispatch_queue_t theQueue;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    if (!theQueue) {
      theQueue = dispatch_queue_create("expo.controller.AssetFilesQueue", DISPATCH_QUEUE_SERIAL);
    }
  });
  return theQueue;
}

- (void)downloadFileFromURL:(NSURL *)url
                     toPath:(NSString *)destinationPath
               successBlock:(EXUpdatesFileDownloaderSuccessBlock)successBlock
                 errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  [self downloadDataFromURL:url successBlock:^(NSData *data, NSURLResponse *response) {
    NSError *error;
    if ([data writeToFile:destinationPath options:NSDataWritingAtomic error:&error]) {
      successBlock(data, response);
    } else {
      errorBlock([NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain
                                     code:1002
                                 userInfo:@{
                                   NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not write to path %@: %@", destinationPath, error.localizedDescription],
                                   NSUnderlyingErrorKey: error
                                 }
                  ], response);
    }
  } errorBlock:errorBlock];
}

- (NSURLRequest *)createManifestRequestWithURL:(NSURL *)url
{
  NSURLRequestCachePolicy cachePolicy = _sessionConfiguration ? _sessionConfiguration.requestCachePolicy : NSURLRequestUseProtocolCachePolicy;
  if (_config.usesLegacyManifest) {
    // legacy manifest loads should ignore cache-control headers from the server and always load remotely
    cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:cachePolicy timeoutInterval:EXUpdatesDefaultTimeoutInterval];
  [self _setManifestHTTPHeaderFields:request];

  return request;
}

- (void)downloadManifestFromURL:(NSURL *)url
                   withDatabase:(EXUpdatesDatabase *)database
                   successBlock:(EXUpdatesFileDownloaderManifestSuccessBlock)successBlock
                     errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  NSURLRequest *request = [self createManifestRequestWithURL:url];
  [self _downloadDataWithRequest:request successBlock:^(NSData *data, NSURLResponse *response) {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
      errorBlock([NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain
                                     code:1040
                                 userInfo:@{
                                   NSLocalizedDescriptionKey: @"response must be a NSHTTPURLResponse",
                                 }
                  ], response);
      return;
    }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSDictionary *headerDictionary = [httpResponse allHeaderFields];
    id headerSignature = headerDictionary[@"expo-manifest-signature"];
    
    NSError *err;
    id parsedJson = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&err];
    if (err) {
      errorBlock(err, response);
      return;
    }

    NSDictionary *updateResponseDictionary = [self _extractUpdateResponseDictionary:parsedJson error:&err];
    if (err) {
      errorBlock(err, response);
      return;
    }

    id bodyManifestString = updateResponseDictionary[@"manifestString"];
    id bodySignature = updateResponseDictionary[@"signature"];
    BOOL isSignatureInBody = bodyManifestString != nil && bodySignature != nil;

    id signature = isSignatureInBody ? bodySignature : headerSignature;
    id manifestString = isSignatureInBody ? bodyManifestString : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      
    // XDL serves unsigned manifests with the `signature` key set to "UNSIGNED".
    // We should treat these manifests as unsigned rather than signed with an invalid signature.
    BOOL isUnsignedFromXDL = [(NSString *)signature isEqualToString:@"UNSIGNED"];

    if (![manifestString isKindOfClass:[NSString class]]) {
      errorBlock([NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain
                                     code:1041
                                 userInfo:@{
                                   NSLocalizedDescriptionKey: @"manifestString should be a string",
                                 }
                  ], response);
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:[(NSString *)manifestString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&err];
    if (err || !manifest || ![manifest isKindOfClass:[NSDictionary class]]) {
      errorBlock([NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain
                                     code:1042
                                 userInfo:@{
                                   NSLocalizedDescriptionKey: @"manifest should be a valid JSON object",
                                 }
                  ], response);
      return;
    }
    NSMutableDictionary *mutableManifest = [manifest mutableCopy];
      
    if (signature != nil && !isUnsignedFromXDL) {
      if (![signature isKindOfClass:[NSString class]]) {
        errorBlock([NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain
                                       code:1043
                                   userInfo:@{
                                     NSLocalizedDescriptionKey: @"signature should be a string",
                                   }
                    ], response);
        return;
      }
      [EXUpdatesCrypto verifySignatureWithData:(NSString *)manifestString
                                     signature:(NSString *)signature
                                        config:self->_config
                                  successBlock:^(BOOL isValid) {
                                                  if (isValid) {
                                                    mutableManifest[@"isVerified"] = @(YES);
                                                    EXUpdatesUpdate *update = [EXUpdatesUpdate updateWithManifest:[mutableManifest copy]
                                                                                                         response:response
                                                                                                           config:self->_config
                                                                                                         database:database];
                                                    successBlock(update);
                                                  } else {
                                                    NSError *error = [NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain code:1003 userInfo:@{NSLocalizedDescriptionKey: @"Manifest verification failed"}];
                                                    errorBlock(error, response);
                                                  }
                                                }
                                    errorBlock:^(NSError *error) {
                                                  errorBlock(error, response);
                                                }
      ];
    } else {
      mutableManifest[@"isVerified"] = @(NO);
      EXUpdatesUpdate *update = [EXUpdatesUpdate updateWithManifest:[(NSDictionary *)mutableManifest copy]
                                                           response:response
                                                             config:self->_config
                                                           database:database];
      successBlock(update);
    }
  } errorBlock:errorBlock];
}

- (void)downloadDataFromURL:(NSURL *)url
               successBlock:(EXUpdatesFileDownloaderSuccessBlock)successBlock
                 errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  // pass any custom cache policy onto this specific request
  NSURLRequestCachePolicy cachePolicy = _sessionConfiguration ? _sessionConfiguration.requestCachePolicy : NSURLRequestUseProtocolCachePolicy;

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:cachePolicy timeoutInterval:EXUpdatesDefaultTimeoutInterval];
  [self _setHTTPHeaderFields:request];

  [self _downloadDataWithRequest:request successBlock:successBlock errorBlock:errorBlock];
}

- (void)_downloadDataWithRequest:(NSURLRequest *)request
                    successBlock:(EXUpdatesFileDownloaderSuccessBlock)successBlock
                      errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
      if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
        NSStringEncoding encoding = [self _encodingFromResponse:response];
        NSString *body = [[NSString alloc] initWithData:data encoding:encoding];
        error = [self _errorFromResponse:httpResponse body:body];
      }
    }

    if (error) {
      errorBlock(error, response);
    } else {
      successBlock(data, response);
    }
  }];
  [task resume];
}

- (nullable NSDictionary *)_extractUpdateResponseDictionary:(id)parsedJson error:(NSError **)error
{
  if ([parsedJson isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary *)parsedJson;
  } else if ([parsedJson isKindOfClass:[NSArray class]]) {
    // TODO: either add support for runtimeVersion or deprecate multi-manifests
    for (id providedManifest in (NSArray *)parsedJson) {
      if ([providedManifest isKindOfClass:[NSDictionary class]] && providedManifest[@"sdkVersion"]){
        NSString *sdkVersion = providedManifest[@"sdkVersion"];
        NSArray<NSString *> *supportedSdkVersions = [_config.sdkVersion componentsSeparatedByString:@","];
        if ([supportedSdkVersions containsObject:sdkVersion]){
          return providedManifest;
        }
      }
    }
  }

  if (error) {
    *error = [NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain code:1009 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No compatible update found at %@. Only %@ are supported.", _config.updateUrl.absoluteString, _config.sdkVersion]}];
  }
  return nil;
}

- (void)_setHTTPHeaderFields:(NSMutableURLRequest *)request
{
  [request setValue:@"ios" forHTTPHeaderField:@"Expo-Platform"];
  [request setValue:@"1" forHTTPHeaderField:@"Expo-Api-Version"];
  [request setValue:@"BARE" forHTTPHeaderField:@"Expo-Updates-Environment"];

  for (NSString *key in _config.requestHeaders) {
    [request setValue:_config.requestHeaders[key] forHTTPHeaderField:key];
  }
}

- (void)_setManifestHTTPHeaderFields:(NSMutableURLRequest *)request
{
  [request setValue:@"application/expo+json,application/json" forHTTPHeaderField:@"Accept"];
  [request setValue:@"true" forHTTPHeaderField:@"Expo-JSON-Error"];
  // as of 2020-11-25, the EAS Update alpha returns an error if Expo-Accept-Signature: true is included in the request
  [request setValue:(_config.usesLegacyManifest ? @"true" : @"false") forHTTPHeaderField:@"Expo-Accept-Signature"];
  [request setValue:_config.releaseChannel forHTTPHeaderField:@"Expo-Release-Channel"];

  NSString *runtimeVersion = _config.runtimeVersion;
  if (runtimeVersion) {
    [request setValue:runtimeVersion forHTTPHeaderField:@"Expo-Runtime-Version"];
  } else {
    [request setValue:_config.sdkVersion forHTTPHeaderField:@"Expo-SDK-Version"];
  }

  NSString *previousFatalError = [EXUpdatesAppLauncherNoDatabase consumeError];
  if (previousFatalError) {
    // some servers can have max length restrictions for headers,
    // so we restrict the length of the string to 1024 characters --
    // this should satisfy the requirements of most servers
    if ([previousFatalError length] > 1024) {
      previousFatalError = [previousFatalError substringToIndex:1024];
    }
    [request setValue:previousFatalError forHTTPHeaderField:@"Expo-Fatal-Error"];
  }

  [self _setHTTPHeaderFields:request];
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler
{
  completionHandler(request);
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
  completionHandler(proposedResponse);
}

#pragma mark - Parsing the response

- (NSStringEncoding)_encodingFromResponse:(NSURLResponse *)response
{
  if (response.textEncodingName) {
    CFStringRef cfEncodingName = (__bridge CFStringRef)response.textEncodingName;
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding(cfEncodingName);
    if (cfEncoding != kCFStringEncodingInvalidId) {
      return CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    }
  }
  // Default to UTF-8
  return NSUTF8StringEncoding;
}

- (NSError *)_errorFromResponse:(NSHTTPURLResponse *)response body:(NSString *)body
{
  NSDictionary *userInfo = @{
                             NSLocalizedDescriptionKey: body,
                             };
  return [NSError errorWithDomain:EXUpdatesFileDownloaderErrorDomain code:response.statusCode userInfo:userInfo];
}

@end

NS_ASSUME_NONNULL_END
