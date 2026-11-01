// MacPanel thermal sensor helper for Apple Silicon.
// Based on the permissively-licensed mac-temp sample by Zack Wagner (2026).
// See ThirdParty/mac-temp-LICENSE.txt and https://github.com/zackwag/mac-temp
//
// Uses private IOHIDEventSystem symbols. Best-effort only: Apple may change
// sensor exposure or deny access on a particular macOS build.

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

// Private IOKit functions are dynamically available, but not in public headers.
typedef struct __IOHIDEventSystemClient *MPHIDSystem;
typedef struct __IOHIDServiceClient *MPHIDService;
typedef struct __IOHIDEvent *MPHIDEvent;

extern MPHIDSystem IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(MPHIDSystem client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(MPHIDSystem client);
extern MPHIDEvent IOHIDServiceClientCopyEvent(MPHIDService service, uint32_t type,
                                             int options, uint64_t timestamp);
extern double IOHIDEventGetFloatValue(MPHIDEvent event, int32_t field);
extern CFTypeRef IOHIDServiceClientCopyProperty(MPHIDService service, CFStringRef key);

int main(void) {
    @autoreleasepool {
        MPHIDSystem system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!system) return 2;
        NSDictionary *matching = @{ @"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(5) };
        IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);
        CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
        if (!services) {
            CFRelease(system);
            return 3;
        }
        BOOL found = NO;
        BOOL preferred = NO;
        double temperature = 0;
        const CFIndex count = CFArrayGetCount(services);
        for (CFIndex i = 0; i < count; i++) {
            MPHIDService sensor = (MPHIDService)CFArrayGetValueAtIndex(services, i);
            CFTypeRef property = IOHIDServiceClientCopyProperty(sensor, CFSTR("Product"));
            NSString *name = nil;
            if (property) {
                if (CFGetTypeID(property) == CFStringGetTypeID()) {
                    name = [(__bridge NSString *)property copy];
                }
                CFRelease(property);
            }
            MPHIDEvent event = IOHIDServiceClientCopyEvent(sensor, 15, 0, 0);
            if (!event) continue;
            // (15 << 16) is the IOHID temperature level field.
            double value = IOHIDEventGetFloatValue(event, (15 << 16));
            CFRelease(event);
            if (!isfinite(value) || value <= 0.0 || value >= 150.0) continue;
            BOOL isCalibrated = [name localizedCaseInsensitiveContainsString:@"tcal"];
            if (!found || (isCalibrated && !preferred)) {
                temperature = value;
                found = YES;
                preferred = isCalibrated;
            }
        }
        CFRelease(services);
        CFRelease(system);
        if (!found) return 4;
        printf("%.1f\n", temperature);
    }
    return 0;
}
