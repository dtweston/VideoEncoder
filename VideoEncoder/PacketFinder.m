//
//  PacketFinder.m
//  VideoEncoder
//
//  Created by Dave Weston on 3/14/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "PacketFinder.h"

typedef enum {
    PAVE_CTRL_FRAME_DATA =0, /* The PaVE is followed by video data */
    PAVE_CTRL_FRAME_ADVERTISEMENT =(1<<0), /* The PaVE is not followed by any data. Used to announce a frame which will be sent on the other socket later. */
    PAVE_CTRL_LAST_FRAME_IN_STREAM =(1<<1), /* Announces the position of the last frame in the current stream */
} parrot_video_encapsulation_control_t;

typedef enum {
    FRAME_TYPE_UNKNNOWN=0,
    FRAME_TYPE_IDR_FRAME, /* headers followed by I-frame */
    FRAME_TYPE_I_FRAME,
    FRAME_TYPE_P_FRAME,
    FRAME_TYPE_HEADERS
} parrot_video_encapsulation_frametypes_t;

typedef struct {
    uint8_t signature[4];
    uint8_t version;
    uint8_t video_codec;
    uint16_t header_size;
    uint32_t payload_size;
    uint16_t encoded_stream_width;
    uint16_t encoded_stream_height;
    uint16_t display_width;
    uint16_t display_height;
    uint32_t frame_number;
    uint32_t timestamp;
    uint8_t total_chunks;
    uint8_t chunk_index;
    uint8_t frame_type;
    uint8_t control;
    uint32_t stream_byte_position_lw;
    uint32_t stream_byte_position_uw;
    uint16_t stream_id;
    uint8_t total_slices;
    uint8_t slice_index;
    uint8_t header1_size;
    uint8_t header2_size;
    uint8_t reserved2[2];
    uint32_t advertised_size;
    uint8_t reserved3[12];
    uint8_t undocumented[4];
    
} __attribute((packed)) parrot_video_encapsulation_t;

@interface Packet ()

@property (nonatomic, readwrite) NSData *sps;
@property (nonatomic, readwrite) NSData *pps;
@property (nonatomic, readwrite) NSData *payload;
@property (nonatomic, readwrite) NSUInteger timestamp;

@end

@implementation Packet

+ (instancetype)packetWithSps:(NSData *)sps pps:(NSData *)pps payload:(NSData *)payload timestamp:(NSUInteger)timestamp
{
    Packet *packet = [[Packet alloc] init];
    packet.sps = sps;
    packet.pps = pps;
    packet.payload = payload;
    packet.timestamp = timestamp;
    
    return packet;
}

@end

@interface PacketFinder ()

@property (strong, nonatomic) NSData *stream;
@property (strong, nonatomic) NSData *remainder;

@end

@implementation PacketFinder

- (instancetype)initWithStream:(NSData *)data
{
    self = [super init];
    if (self) {
        _stream = data;
        _remainder = data;
    }
    
    return self;
}

- (Packet *)nextPacket
{
    parrot_video_encapsulation_t packet;
    
    [self.remainder getBytes:&packet length:sizeof(parrot_video_encapsulation_t)];
    
    if (packet.signature[0] != 'P' ||
        packet.signature[1] != 'a' ||
        packet.signature[2] != 'V' ||
        packet.signature[3] != 'E') {
        
        NSLog(@"Invalid packet header signature found!");
        
        return nil;
    }
    
    NSUInteger start = packet.header_size;
    size_t payloadSize = packet.payload_size;
    NSData *payload = [self.remainder subdataWithRange:NSMakeRange(start, payloadSize)];
    
    NSData *sps = nil;
    NSData *pps = nil;
    NSData *data = nil;
    
    if (packet.header1_size && packet.header2_size) {
        uint32_t spsSize = packet.header1_size - sizeof(uint32_t);
        uint32_t ppsSize = packet.header2_size - sizeof(uint32_t);
        
        NSRange spsRange = NSMakeRange(sizeof(uint32_t), spsSize);
        NSUInteger ppsStart = NSMaxRange(spsRange) + sizeof(uint32_t);
        NSRange ppsRange = NSMakeRange(ppsStart, ppsSize);
        NSRange dataRange = NSMakeRange(NSMaxRange(ppsRange) + sizeof(uint32_t), payloadSize - NSMaxRange(ppsRange) - sizeof(uint32_t));
        sps = [payload subdataWithRange:spsRange];
        pps = [payload subdataWithRange:ppsRange];
        
        data = [payload subdataWithRange:dataRange];
    }
    else {
        data = payload;
    }
    
    NSString *frameType = @"unknown";
    switch (packet.frame_type) {
        case FRAME_TYPE_IDR_FRAME:
            frameType = @"IDR";
            break;
        case FRAME_TYPE_I_FRAME:
            frameType = @"I";
            break;
        case FRAME_TYPE_P_FRAME:
            frameType = @"P";
            break;
        case FRAME_TYPE_HEADERS:
            frameType = @"headers";
            break;
            
        default:
            break;
    }
    
    NSLog(@"Stream ID: %u, Frame type: %@, frame number: %u timestamp: %d", packet.stream_id, frameType, packet.frame_number, packet.timestamp);
    NSLog(@"Packet SPS: %ld PPS: %ld Payload: %ld", sps.length, pps.length, data.length);

    NSData *remainder = [self.remainder subdataWithRange:NSMakeRange(start+payloadSize, [self.remainder length]-start-payloadSize)];
    self.remainder = remainder;
    
    return [Packet packetWithSps:sps pps:pps payload:data timestamp:packet.timestamp];
}

@end
