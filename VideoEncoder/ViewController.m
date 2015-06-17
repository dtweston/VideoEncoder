//
//  ViewController.m
//  VideoEncoder
//
//  Created by Dave Weston on 3/11/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

@import AVFoundation;
@import VideoToolbox;

#import "PacketFinder.h"

#import "ViewController.h"

NSString *NSStringFromOSStatus(OSStatus errCode)
{
    if (errCode == noErr)
        return @"noErr";
    char message[5] = {0};
    *(UInt32*) message = CFSwapInt32HostToBig(errCode);
    return [NSString stringWithCString:message encoding:NSASCIIStringEncoding];
}

@interface ViewController ()

@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) VTCompressionSessionRef compressSession;
@property (nonatomic, assign) VTDecompressionSessionRef decompressSession;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    AVSampleBufferDisplayLayer *displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
    displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    displayLayer.backgroundColor = [[UIColor greenColor] CGColor];
    displayLayer.frame = self.view.layer.bounds;
    [self.view.layer addSublayer:displayLayer];
    
    self.displayLayer = displayLayer;
    
    CMTimebaseRef controlTimebase;
    CMTimebaseCreateWithMasterClock( CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
    
    self.displayLayer.controlTimebase = controlTimebase;
    CMTimebaseSetTime(self.displayLayer.controlTimebase, CMTimeMake(184000, 1000));
    CMTimebaseSetRate(self.displayLayer.controlTimebase, 1000.0);
    
    [[NSNotificationCenter defaultCenter] addObserverForName:AVSampleBufferDisplayLayerFailedToDecodeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSError *error = note.userInfo[AVSampleBufferDisplayLayerFailedToDecodeNotificationErrorKey];
        id obj = error.userInfo[AVErrorMediaSubTypeKey];
        OSStatus status = [obj[0] intValue];
        NSLog(@"Failed to decode: %@", error);
        NSLog(@"Media subtype: %@", NSStringFromOSStatus(status));
        
        NSError *error2 = error.userInfo[NSUnderlyingErrorKey];
        NSLog(@"Underlying error: %@", error2);
    }];
}

- (void)viewDidLayoutSubviews
{
    self.displayLayer.frame = self.view.layer.bounds;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:@"drone" withExtension:@"h264"];
    NSData *data = [NSData dataWithContentsOfURL:fileUrl];
    
    PacketFinder *finder = [[PacketFinder alloc] initWithStream:data];
    
    AVSampleBufferDisplayLayer *layer = self.displayLayer;
    __block CMFormatDescriptionRef format = NULL;
    [layer requestMediaDataWhenReadyOnQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0) usingBlock:^{
        while (layer.isReadyForMoreMediaData) {
            Packet *packet = nil;
            if ((packet = [finder nextPacket]) != nil) {
                
                if (packet.sps && packet.pps) {
                    const uint8_t *pointers[2] = { (const uint8_t *)[packet.sps bytes], (const uint8_t *)[packet.pps bytes] };
                    size_t sizes[2] = { [packet.sps length], [packet.pps length] };
                    
                    OSStatus err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, pointers, sizes, 4, &format);
                    NSAssert(err == noErr, @"Unable to create video fromat description: %d", (int)err);
                }
                
                CMBlockBufferRef blockBuffer;
                OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, [packet.payload length] + 4, kCFAllocatorDefault, NULL, 0, [packet.payload length] + 4, 0, &blockBuffer);
                NSAssert(status == noErr, @"Unable to create block buffer");
                
                size_t offset = 0;
                uint32_t nalu_length = htonl(packet.payload.length);
                CMBlockBufferReplaceDataBytes(&nalu_length, blockBuffer, offset, 4);
                offset += 4;
                CMBlockBufferReplaceDataBytes([packet.payload bytes], blockBuffer, offset, [packet.payload length]);
                offset += [packet.payload length];
                
                CMSampleBufferRef sampleBuffer;
                CMSampleTimingInfo timing[1];
                timing[0].duration = kCMTimeIndefinite;
                timing[0].presentationTimeStamp = CMTimeMakeWithSeconds((Float64)packet.timestamp/1000.0, 1000);
                timing[0].decodeTimeStamp = kCMTimeInvalid;
                size_t size[1] = { offset };
                status = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, YES, NULL, NULL, format, 1, 1, timing, 1, size, &sampleBuffer);
                NSAssert(status == noErr, @"Unable to create sample buffer");
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [layer enqueueSampleBuffer:sampleBuffer];
                });
            }
            else {
                [layer stopRequestingMediaData];
            }
        }
    }];
}

@end
