// Lab-only helper for a rootless test phone. Trust exactly one ephemeral
// localhost TLS certificate, through trustd's API, and remove it after the run.
// SPI declarations: apple-oss-distributions/Security/OSX/sec/Security/SecTrustStore.h
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <dlfcn.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 64;
        NSData *data = [NSData dataWithContentsOfFile:@(argv[2])];
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)data);
        if (!certificate) return 65;
        void *(*domain)(uint32_t) = dlsym(RTLD_DEFAULT, "SecTrustStoreForDomain");
        OSStatus (*set)(void *, SecCertificateRef, CFTypeRef) = dlsym(RTLD_DEFAULT, "SecTrustStoreSetTrustSettings");
        OSStatus (*remove)(void *, SecCertificateRef) = dlsym(RTLD_DEFAULT, "SecTrustStoreRemoveCertificate");
        Boolean (*contains)(void *, SecCertificateRef) = dlsym(RTLD_DEFAULT, "SecTrustStoreContains");
        if (!domain || !set || !remove || !contains) return 69;
        void *store = domain(2);
        BOOL existed = contains(store, certificate);
        SecPolicyRef policy = SecPolicyCreateSSL(true, CFSTR("localhost"));
        NSString *action = @(argv[1]);
        OSStatus status = 0;
        if ([action isEqual:@"add"]) {
            if (existed) return 73;
            NSDictionary *settings = @{
                @"kSecTrustSettingsResult": @1,
                @"kSecTrustSettingsPolicy": (__bridge id)policy,
                @"kSecTrustSettingsPolicyString": @"localhost"
            };
            status = set(store, certificate, (__bridge CFTypeRef)settings);
        } else if ([action isEqual:@"remove"]) {
            status = remove(store, certificate);
        } else if (![action isEqual:@"check"]) {
            return 64;
        }
        BOOL present = contains(store, certificate);
        SecTrustRef trust = NULL;
        SecTrustCreateWithCertificates(certificate, policy, &trust);
        BOOL trusted = trust && SecTrustEvaluateWithError(trust, NULL);
        printf("{\"status\":%d,\"present\":%s,\"trustedLocalhost\":%s}\n", (int)status,
               present ? "true" : "false", trusted ? "true" : "false");
        if (trust) CFRelease(trust);
        CFRelease(policy);
        CFRelease(certificate);
        return status || ([action isEqual:@"add"] && (!present || !trusted)) ||
               ([action isEqual:@"remove"] && present) ? 1 : 0;
    }
}
