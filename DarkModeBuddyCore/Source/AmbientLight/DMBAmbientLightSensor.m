//
//  DMBAmbientLightSensor.m
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

#import <DarkModeBuddyCore/DarkModeBuddyCore.h>

@import os.log;

#import <IOKit/hidsystem/IOHIDServiceClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;

#define kAmbientLightSensorEvent 12

#define IOHIDEventFieldBase(type) (type << 16)

extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
extern double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);

// BezelServices.framework
extern IOHIDServiceClientRef ALCALSCopyALSServiceClient(void);

@interface DMBAmbientLightSensor ()

@property (nonatomic, readonly) IOHIDEventRef event;
@property (nonatomic, assign) double value;

@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) os_log_t log;

@end

@implementation DMBAmbientLightSensor
{
    IOHIDServiceClientRef _client;
    IOHIDEventRef _event;
}

- (instancetype)init
{
    if (!(self = [super init])) return nil;
    
    _value = -1;
    _updateInterval = 5;
    
    self.log = os_log_create(kDarkModeBuddyCoreSubsystemName, "AmbientLightSensor");
    
    return self;
}

- (IOHIDEventRef)event
{
    if (!_client) _client = ALCALSCopyALSServiceClient();
    
    if (_client) {
        _event = IOHIDServiceClientCopyEvent(_client, kAmbientLightSensorEvent, 0, 0);
    }
    
    return _event;
}

- (void)_read
{
    if (!self.event) {
        self.value = -1;
        return;
    }
    
    self.value = IOHIDEventGetFloatValue(self.event, IOHIDEventFieldBase(kAmbientLightSensorEvent));
}

- (void)setUpdateInterval:(NSTimeInterval)updateInterval
{
    if (updateInterval == _updateInterval) return;
    
    assert(updateInterval > 0);
    
    _updateInterval = updateInterval;
    
    if (self.updateTimer) [self _setupUpdateTimer];
}

- (void)activate
{
    [self _setupUpdateTimer];
    [self _read];
}

- (void)invalidate
{
    [self _tearDownUpdateTimer];
}

- (BOOL)isPresent
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DMBFakeSensorSupported"]) return YES;
    
    return self.event != NULL;
}

- (void)_tearDownUpdateTimer
{
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)_setupUpdateTimer
{
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:self.updateInterval
                                                        target:self
                                                      selector:@selector(_read)
                                                      userInfo:nil
                                                       repeats:YES];
    self.updateTimer.tolerance = self.updateInterval / 2;
}

- (void)dealloc
{
    [self _tearDownUpdateTimer];
    if (_client) CFRelease(_client);
    if (_event) CFRelease(_event);
}

@end
