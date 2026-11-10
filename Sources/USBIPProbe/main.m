#import <Foundation/Foundation.h>
#import <IOUSBHost/IOUSBHostControllerInterface.h>
#import <unistd.h>

// Use the SDK's controller/port capability layout; never infer access from SIP text.
int main(void) {
  @autoreleasepool {
    if (geteuid() != 0) {
      puts("{\"schemaVersion\":1,\"state\":\"requires_root\",\"available\":false}");
      return 2;
    }
    IOUSBHostCIMessage messages[2] = {
      {.control = (IOUSBHostCIMessageTypeControllerCapabilities << IOUSBHostCIMessageControlTypePhase)
          | IOUSBHostCIMessageControlNoResponse | IOUSBHostCIMessageControlValid
          | (1 << IOUSBHostCICapabilitiesMessageControlPortCountPhase),
       .data0 = (1 << IOUSBHostCICapabilitiesMessageData0CommandTimeoutThresholdPhase)
          | (2 << IOUSBHostCICapabilitiesMessageData0ConnectionLatencyPhase)},
      {.control = (IOUSBHostCIMessageTypePortCapabilities << IOUSBHostCIMessageControlTypePhase)
          | IOUSBHostCIMessageControlNoResponse | IOUSBHostCIMessageControlValid
          | (1 << IOUSBHostCIPortCapabilitiesMessageControlPortNumberPhase),
       .data0 = ((907 / 8) << IOUSBHostCIPortCapabilitiesMessageData0MaxPowerPhase)}
    };
    NSError *error = nil;
    IOUSBHostControllerInterface *controller = [[IOUSBHostControllerInterface alloc]
        initWithCapabilities:[NSData dataWithBytes:messages length:sizeof(messages)]
        queue:nil interruptRateHz:1000 error:&error
        commandHandler:^(IOUSBHostControllerInterface *c, IOUSBHostCIMessage command) {}
        doorbellHandler:^(IOUSBHostControllerInterface *c, IOUSBHostCIDoorbell *bells, uint32_t count) {}
        interestHandler:NULL];
    BOOL available = controller != nil;
    [controller destroy];
    NSDictionary *result = @{@"schemaVersion": @1, @"available": @(available),
      @"state": available ? @"available" : @"unavailable",
      @"detail": error.localizedDescription ?: @"Controller creation succeeded; no device attached."};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    fwrite(json.bytes, 1, json.length, stdout);
    puts("");
    return available ? 0 : 3;
  }
}
