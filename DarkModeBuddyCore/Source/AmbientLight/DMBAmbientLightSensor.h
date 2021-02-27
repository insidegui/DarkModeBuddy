//
//  DMBAmbientLightSensor.h
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DMBAmbientLightSensor : NSObject

@property (nonatomic, readonly) double value;
@property (nonatomic, assign) NSTimeInterval updateInterval;

- (void)activate;
- (void)invalidate;
- (void)update;

@property (nonatomic, readonly) BOOL isPresent;

+ (BOOL)hardwareUsesLegacySensor;


@end

NS_ASSUME_NONNULL_END
