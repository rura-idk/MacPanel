// MacPanelHardware — read-only hardware sampler for macOS.
// SMC IOKit protocol; modeled on public examples of AppleSMC readers.
// Only reads keys (never calls the SMC write command or changes fan control).
// Emits a small JSON object on stdout; absent sensors are omitted.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <math.h>
#import <stdint.h>
#import <string.h>

#define MP_SMC_CALL 2
#define MP_SMC_READ 5
#define MP_SMC_INFO 9
#define MP_KEY_SIZE 32

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } MPVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } MPPLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } MPKeyInfo;
typedef struct {
    uint32_t key;
    MPVersion vers;
    MPPLimit pLimitData;
    MPKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[MP_KEY_SIZE];
} MPKeyData;
_Static_assert(sizeof(MPKeyData) == 80, "Unexpected AppleSMC ABI layout");

static uint32_t MPFourCC(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) |
           ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) |
            (uint32_t)(uint8_t)s[3];
}

static BOOL MPCall(io_connect_t conn, MPKeyData *in, MPKeyData *out) {
    size_t outSize = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(conn, MP_SMC_CALL,
                                                      in, sizeof(*in), out, &outSize);
    return result == KERN_SUCCESS && outSize == sizeof(*out) && out->result == 0;
}

static BOOL MPReadKey(io_connect_t conn, const char key[5], double *value) {
    MPKeyData in = {0}, out = {0};
    in.key = MPFourCC(key);
    in.data8 = MP_SMC_INFO;
    if (!MPCall(conn, &in, &out)) return NO;
    const uint32_t size = out.keyInfo.dataSize;
    const uint32_t type = out.keyInfo.dataType;
    if (size < 1 || size > MP_KEY_SIZE) return NO;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = MPFourCC(key);
    in.keyInfo.dataSize = size;
    in.data8 = MP_SMC_READ;
    if (!MPCall(conn, &in, &out)) return NO;

    const uint8_t *b = out.bytes;
    if (type == MPFourCC("flt ") && size == 4) {
        // On Apple Silicon SMC fan values use native-endian IEEE 754 float.
        float f = 0;
        memcpy(&f, b, sizeof(f));
        if (!isfinite(f)) return NO;
        *value = (double)f;
    } else if (type == MPFourCC("fpe2") && size == 2) {
        *value = (double)((b[0] << 8) | b[1]) / 4.0;
    } else if (type == MPFourCC("ui8 ") && size == 1) {
        *value = b[0];
    } else if (type == MPFourCC("ui16") && size == 2) {
        *value = (b[0] << 8) | b[1];
    } else {
        return NO;
    }
    return isfinite(*value);
}

static NSArray<NSDictionary *> *MPFans(void) {
    io_service_t service = IOServiceGetMatchingService(MACH_PORT_NULL,
                                                       IOServiceMatching("AppleSMC"));
    if (!service) return @[];
    io_connect_t conn = IO_OBJECT_NULL;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    if (status != KERN_SUCCESS || !conn) return @[];

    NSMutableArray<NSDictionary *> *fans = [NSMutableArray array];
    double totalFans = 0;
    // If FNum is not exposed, attempt fan index 0 as a limited fallback.
    BOOL knownCount = MPReadKey(conn, "FNum", &totalFans);
    NSUInteger count = knownCount ? (NSUInteger)fmin(fmax(totalFans, 0), 8) : 1;
    for (NSUInteger i = 0; i < count; i++) {
        char key[5];
        snprintf(key, sizeof(key), "F%luAc", (unsigned long)i);
        double rpm = 0;
        if (!MPReadKey(conn, key, &rpm) || rpm < 0 || rpm > 30000) continue;
        NSMutableDictionary *entry = [@{ @"index": @(i), @"rpm": @(rpm) } mutableCopy];
        struct { const char *suffix; NSString *field; } extras[] = {
            {"Tg", @"target"}, {"Mn", @"minimum"}, {"Mx", @"maximum"}
        };
        for (NSUInteger j = 0; j < sizeof(extras)/sizeof(extras[0]); j++) {
            snprintf(key, sizeof(key), "F%lu%s", (unsigned long)i, extras[j].suffix);
            double value = 0;
            if (MPReadKey(conn, key, &value) && value >= 0 && value <= 30000) {
                entry[extras[j].field] = @(value);
            }
        }
        [fans addObject:entry];
    }
    IOServiceClose(conn);
    return fans;
}

static NSNumber *MPGPUUtilization(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, IOServiceMatching("IOAccelerator"),
                                    &iterator) != KERN_SUCCESS) return nil;
    NSNumber *maximum = nil;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef property = IORegistryEntryCreateCFProperty(service,
                                                               CFSTR("PerformanceStatistics"),
                                                               kCFAllocatorDefault, 0);
        if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
            NSDictionary *stats = (__bridge NSDictionary *)property;
            for (NSString *name in @[@"Device Utilization %", @"GPU Activity(%)", @"Renderer Utilization %"]) {
                id n = stats[name];
                if ([n isKindOfClass:[NSNumber class]]) {
                    double v = [n doubleValue];
                    if (isfinite(v) && v >= 0 && v <= 100 &&
                        (!maximum || v > maximum.doubleValue)) maximum = @(v);
                }
            }
        }
        if (property) CFRelease(property);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return maximum;
}

static NSDictionary *MPDiskCounters(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL,
                                    IOServiceMatching("IOBlockStorageDriver"),
                                    &iterator) != KERN_SUCCESS) return @{};
    uint64_t readBytes = 0, writtenBytes = 0;
    BOOL found = NO;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef property = IORegistryEntryCreateCFProperty(service, CFSTR("Statistics"),
                                                               kCFAllocatorDefault, 0);
        if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
            NSDictionary *stats = (__bridge NSDictionary *)property;
            id r = stats[@"Bytes (Read)"];
            id w = stats[@"Bytes (Write)"];
            if ([r isKindOfClass:[NSNumber class]] && [w isKindOfClass:[NSNumber class]]) {
                readBytes += [r unsignedLongLongValue];
                writtenBytes += [w unsignedLongLongValue];
                found = YES;
            }
        }
        if (property) CFRelease(property);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return found ? @{ @"diskRead": @(readBytes), @"diskWrite": @(writtenBytes) } : @{};
}

int main(void) {
    @autoreleasepool {
        NSMutableDictionary *metrics = [@{ @"fans": MPFans() } mutableCopy];
        NSNumber *gpu = MPGPUUtilization();
        if (gpu) metrics[@"gpuPercent"] = gpu;
        [metrics addEntriesFromDictionary:MPDiskCounters()];
        NSData *json = [NSJSONSerialization dataWithJSONObject:metrics options:0 error:nil];
        if (!json) return 2;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
