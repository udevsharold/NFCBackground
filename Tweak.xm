#import "headers.h"
#import "NSData+Conversion.h"

extern "C" CFNotificationCenterRef CFNotificationCenterGetDistributedCenter(void);

%hook NFBackgroundTagReadingManager
- (id)initWithQueue:(id)arg1 driverWrapper:(id)arg2 lpcdHWSupport:(unsigned char)arg3 {
	%log;
	return %orig(arg1, arg2, 1);
}

- (void)handleDetectedTags:(id)tagCollection {
	NSArray *tags = [tagCollection allObjects];
	HBLogDebug(@"=== Detected tags: %lu ===", tags.count);

	NFDriverWrapper *driver = MSHookIvar<NFDriverWrapper *>(self, "_driverWrapper");

	NSMutableArray *compiledData = [[NSMutableArray alloc] init];
	for(NFTagInternal *tag in tags) {
		NSString *uid = [tag.tagID hexadecimalString];

		NSMutableArray *records = [[NSMutableArray alloc] init];
		[self _readNDEFFromTag:tag];
		id messageInternal = [self _readNDEFFromTag:tag];
		NFCNDEFMessage *ndefMessage = [[NFCNDEFMessage alloc] initWithNFNdefMessage: messageInternal];
		for(NFCNDEFPayload *payload in ndefMessage.records) {
			NSString *payloadData = [[NSString alloc] initWithData:payload.payload encoding:NSUTF8StringEncoding];
			NSString *type = [[NSString alloc] initWithData:payload.type encoding:NSUTF8StringEncoding];
			[records addObject:@{@"payload" : payloadData, @"type" : type}];
		}

		[compiledData addObject:@{@"uid" : uid, @"records" : [records copy]}];
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		CFDictionaryRef userInfo = (__bridge CFDictionaryRef)@{@"data" : [compiledData copy]};
		CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
		CFNotificationCenterPostNotification(center, CFSTR("nfcbackground.newtag"), NULL, userInfo, TRUE);
	});

	[NSThread sleepForTimeInterval:1.0];
	[driver restartDiscovery];
	HBLogDebug(@"exit");
}
%end