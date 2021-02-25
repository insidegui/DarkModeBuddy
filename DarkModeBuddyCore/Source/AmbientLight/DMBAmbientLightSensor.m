//
//  DMBAmbientLightSensor.m
//  DarkModeBuddyCore
//
//  Created by Guilherme Rambo on 23/02/21.
//

#import <DarkModeBuddyCore/DarkModeBuddyCore.h>

@import os.log;

#import <IOKit/hidsystem/IOHIDServiceClient.h>
#import <IOKit/IOKitLib.h>

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

    io_connect_t _legacySensorDataPort;
    BOOL _legacySensorInitializedSuccessfully;
}

- (instancetype)init
{
    if (!(self = [super init])) return nil;
    
    _value = -1;
    _updateInterval = 5;
    _legacySensorInitializedSuccessfully = NO;
    
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
        [self _readLegacy];
        return;
    }
    
    self.value = IOHIDEventGetFloatValue(self.event, IOHIDEventFieldBase(kAmbientLightSensorEvent));
}

- (void)_initializeLegacySensorObject
{
    if (_legacySensorInitializedSuccessfully) return;
    
    io_service_t legacySensorObject = 0;
    
    if (!_legacySensorInitializedSuccessfully) {
        legacySensorObject = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleLMUController"));
        if (!legacySensorObject) {
            os_log_fault(self.log, "Failed to initialize AppleLMUController");
            return;
        }
    }
    
    if (IOServiceOpen(legacySensorObject, mach_task_self(), 0, &_legacySensorDataPort) != KERN_SUCCESS) {
        os_log_fault(self.log, "Failed to open AppleLMUController service");
        return;
    }
    
    IOObjectRelease(legacySensorObject);
    
    _legacySensorInitializedSuccessfully = YES;
    
    os_log_debug(self.log, "Initialized legacy sensor");
}

- (void)_readLegacy
{
    [self _initializeLegacySensorObject];
    
    if (!_legacySensorInitializedSuccessfully) {
        self.value = -1;
        return;
    }
    
    uint32_t outputs = 2;
    uint64_t values[outputs];

    if (IOConnectCallMethod(_legacySensorDataPort, 0, nil, 0, nil, 0, values, &outputs, nil, 0) == KERN_SUCCESS) {
        double v = (double)(3 * values[0] / 100000 - 1.5);
        double lux = (v > 0) ? v : 0.0;
        
        self.value = lux;

//        os_log_debug(self.log, "New value (legacy): %{public}.2f", self.value);
    } else {
        os_log_fault(self.log, "Failed to read legacy sensor value");
    }
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
    
    return self.event != NULL || _legacySensorInitializedSuccessfully;
}

+ (BOOL)hardwareUsesLegacySensor
{
    static BOOL _usesLegacySensor;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _usesLegacySensor = (ALCALSCopyALSServiceClient() == NULL);
    });
    return _usesLegacySensor;
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
    if (_legacySensorInitializedSuccessfully) IOConnectRelease(_legacySensorDataPort);
}

@end
