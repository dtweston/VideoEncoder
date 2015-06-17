//
//  PacketFinder.h
//  VideoEncoder
//
//  Created by Dave Weston on 3/14/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Packet : NSObject

@property (nonatomic, readonly) NSData *sps;
@property (nonatomic, readonly) NSData *pps;
@property (nonatomic, readonly) NSData *payload;

@end

@interface PacketFinder : NSObject

- (instancetype)initWithStream:(NSData *)data;
- (Packet *)nextPacket;

@end
