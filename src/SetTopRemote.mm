#import <Cocoa/Cocoa.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>

static constexpr CGFloat W = 390, H = 624;
static NSColor *Ink(unsigned rgb) {
  return [NSColor colorWithCalibratedRed:((rgb >> 16) & 255) / 255.0
                                  green:((rgb >> 8) & 255) / 255.0
                                   blue:(rgb & 255) / 255.0 alpha:1];
}
static NSRect Frame(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
  return NSMakeRect(x, H - y - h, w, h);
}
static void Surface(NSView *view, unsigned color, CGFloat radius) {
  view.wantsLayer = YES;
  view.layer.backgroundColor = Ink(color).CGColor;
  view.layer.cornerRadius = radius;
  view.layer.masksToBounds = YES;
}
static NSTextField *Text(NSView *parent, NSString *string, NSRect frame, CGFloat size,
                         unsigned color, NSFontWeight weight) {
  NSTextField *t = [NSTextField labelWithString:string];
  t.frame = frame;
  t.font = [NSFont systemFontOfSize:size weight:weight];
  t.textColor = Ink(color);
  t.lineBreakMode = NSLineBreakByTruncatingTail;
  [parent addSubview:t];
  return t;
}
static NSButton *Action(NSView *parent, NSString *title, NSRect frame,
                        unsigned color, CGFloat radius, CGFloat size,
                        id target, SEL selector, NSInteger tag) {
  NSButton *b = [[NSButton alloc] initWithFrame:frame];
  b.title = title;
  b.bezelStyle = NSBezelStyleRegularSquare;
  b.bordered = NO;
  Surface(b, color, radius);
  b.font = [NSFont systemFontOfSize:size weight:NSFontWeightSemibold];
  b.contentTintColor = Ink(0xF8FAFF);
  b.target = target;
  b.action = selector;
  b.tag = tag;
  b.toolTip = title;
  b.accessibilityLabel = title;
  [parent addSubview:b];
  return b;
}
static NSButton *Icon(NSView *parent, NSString *symbol, NSString *accessible,
                      NSRect frame, unsigned color, CGFloat radius, CGFloat pointSize,
                      id target, SEL selector, NSInteger tag) {
  NSButton *b = Action(parent, @"", frame, color, radius, 14, target, selector, tag);
  NSImageSymbolConfiguration *config =
    [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightMedium];
  NSImage *image = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:accessible]
                    imageWithSymbolConfiguration:config];
  b.image = image;
  b.imagePosition = NSImageOnly;
  b.toolTip = accessible;
  b.accessibilityLabel = accessible;
  return b;
}
@interface TopView : NSView @end
@implementation TopView
- (BOOL)isFlipped { return YES; }
@end

// Touchpad input stays inside the app. The Mac's own pointer never gets captured.
@interface TouchPadView : NSView
@property (nonatomic, copy) void (^onStep)(NSInteger);
@property (nonatomic, copy) void (^onTap)(NSPoint);
@property (nonatomic, copy) void (^onSwipe)(NSPoint, NSPoint, NSInteger);
@property (nonatomic, copy) void (^onMove)(NSPoint);
@property (nonatomic) BOOL pointerMode;
@end
@implementation TouchPadView {
  NSPoint _start, _previous;
  NSTimeInterval _startTime, _lastMove;
  CGFloat _motion, _wheelX, _wheelY;
  BOOL _stepped;
  NSTrackingArea *_tracking;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (NSView *)hitTest:(NSPoint)point {
  // Decorative labels inside the pad must not intercept gesture events.
  NSPoint local = [self convertPoint:point fromView:self.superview];
  return NSPointInRect(local, self.bounds) ? self : nil;
}
- (void)updateTrackingAreas {
  if (_tracking) [self removeTrackingArea:_tracking];
  _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
    options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
    owner:self userInfo:nil];
  [self addTrackingArea:_tracking];
  [super updateTrackingAreas];
}
- (NSPoint)padPoint:(NSEvent *)event {
  NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
  return NSMakePoint(MAX(0, MIN(self.bounds.size.width, p.x)),
                     MAX(0, MIN(self.bounds.size.height, p.y)));
}
- (void)mouseDown:(NSEvent *)event {
  _start = _previous = [self padPoint:event];
  _startTime = event.timestamp;
  _motion = 0;
  _stepped = NO;
  _wheelX = _wheelY = 0;
}
- (void)mouseDragged:(NSEvent *)event {
  NSPoint p = [self padPoint:event];
  CGFloat dx = p.x - _previous.x, dy = p.y - _previous.y;
  _motion += hypot(dx, dy);
  if (!self.pointerMode) {
    // Emit steps while dragging so long swipes feel responsive.
    CGFloat travel = hypot(p.x - _previous.x, p.y - _previous.y);
    if (travel > 0) {
      _wheelX += dx; _wheelY += dy;
      CGFloat dominant = fabs(_wheelX) > fabs(_wheelY) ? _wheelX : _wheelY;
      if (fabs(dominant) >= 43) {
        NSInteger key = fabs(_wheelX) > fabs(_wheelY)
          ? (_wheelX > 0 ? 22 : 21) : (_wheelY > 0 ? 20 : 19);
        if (self.onStep) self.onStep(key);
        _wheelX = _wheelY = 0;
        _stepped = YES;
      }
    }
  } else if (event.timestamp - _lastMove > .085) {
    _lastMove = event.timestamp;
    if (self.onMove) self.onMove(p);
  }
  _previous = p;
}
- (void)mouseUp:(NSEvent *)event {
  NSPoint end = [self padPoint:event];
  CGFloat dx = end.x - _start.x, dy = end.y - _start.y;
  if (self.pointerMode) {
    if (hypot(dx, dy) < 12 && _motion < 18) {
      if (self.onTap) self.onTap(end);
    } else if (self.onSwipe) {
      NSInteger ms = (NSInteger)MAX(120, MIN(600, (event.timestamp - _startTime) * 1000));
      self.onSwipe(_start, end, ms);
    }
  } else if (!_stepped) {
    if (hypot(dx, dy) < 22 && _motion < 26) {
      if (self.onStep) self.onStep(23); // DPAD_CENTER
    } else {
      NSInteger key = fabs(dx) > fabs(dy) ? (dx > 0 ? 22 : 21) : (dy > 0 ? 20 : 19);
      if (self.onStep) self.onStep(key);
    }
  }
  _wheelX = _wheelY = 0;
}
- (void)mouseMoved:(NSEvent *)event {
  if (!self.pointerMode || event.timestamp - _lastMove < .085) return;
  _lastMove = event.timestamp;
  if (self.onMove) self.onMove([self padPoint:event]);
}
- (void)scrollWheel:(NSEvent *)event {
  if (self.pointerMode) return;
  CGFloat scale = event.hasPreciseScrollingDeltas ? 1 : 12;
  _wheelX += event.scrollingDeltaX * scale;
  _wheelY += event.scrollingDeltaY * scale;
  if (fabs(_wheelY) >= 22 || fabs(_wheelX) >= 22) {
    NSInteger key = fabs(_wheelY) >= fabs(_wheelX)
      ? (_wheelY > 0 ? 19 : 20) : (_wheelX > 0 ? 21 : 22);
    if (self.onStep) self.onStep(key);
    _wheelX = _wheelY = 0;
  }
}
@end

// Scan only the active LAN's IPv4 subnet; at most one /24.
static NSArray<NSString *> *LANHosts(void) {
  struct ifaddrs *head = nullptr;
  if (getifaddrs(&head) != 0) return @[];
  uint32_t ip = 0, mask = 0;
  int best = -1;
  for (struct ifaddrs *entry = head; entry; entry = entry->ifa_next) {
    if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET ||
        !(entry->ifa_flags & IFF_UP) || (entry->ifa_flags & IFF_LOOPBACK)) continue;
    NSString *name = @(entry->ifa_name);
    if ([name hasPrefix:@"utun"] || [name hasPrefix:@"awdl"] || [name hasPrefix:@"llw"]) continue;
    int score = [name isEqualToString:@"en0"] ? 3 : ([name hasPrefix:@"en"] ? 2 : 1);
    if (score < best) continue;
    uint32_t candidate = ntohl(((struct sockaddr_in *)entry->ifa_addr)->sin_addr.s_addr);
    if ((candidate >> 24) == 169 || candidate == 0) continue;
    ip = candidate;
    mask = ntohl(((struct sockaddr_in *)entry->ifa_netmask)->sin_addr.s_addr);
    best = score;
  }
  freeifaddrs(head);
  if (!ip) return @[];
  // A /16 or larger LAN scans just the user's /24 for speed and safety.
  if (mask < 0xffffff00U) mask = 0xffffff00U;
  uint32_t network = ip & mask, broadcast = network | ~mask;
  NSMutableArray<NSString *> *hosts = [NSMutableArray array];
  for (uint32_t address = network + 1; address < broadcast && hosts.count < 254; ++address) {
    if (address == ip) continue;
    struct in_addr value = { .s_addr = htonl(address) };
    char dotted[INET_ADDRSTRLEN] = {};
    if (inet_ntop(AF_INET, &value, dotted, sizeof dotted)) [hosts addObject:@(dotted)];
  }
  return hosts;
}
static BOOL OpenADBPort(NSString *ip) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return NO;
  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  struct sockaddr_in addr = {};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(5555);
  if (inet_pton(AF_INET, ip.UTF8String, &addr.sin_addr) != 1) { close(fd); return NO; }
  int result = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
  if (result != 0 && errno == EINPROGRESS) {
    struct pollfd pfd = { fd, POLLOUT, 0 };
    result = poll(&pfd, 1, 320);
    if (result > 0) {
      int error = 0;
      socklen_t len = sizeof(error);
      result = getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &len) == 0 && error == 0 ? 0 : -1;
    } else result = -1;
  }
  close(fd);
  return result == 0;
}

@interface RemoteAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate,
  NSNetServiceBrowserDelegate, NSNetServiceDelegate>
- (void)sendKey:(NSInteger)key;
- (void)connectAddress:(NSString *)address port:(NSInteger)port;
@end

@implementation RemoteAppDelegate {
  NSStatusItem *_statusItem;
  NSPanel *_panel;
  NSView *_discovery, *_remote;
  NSView *_list;
  NSTextField *_scanStatus, *_connectStatus, *_remoteTitle, *_remoteDetail;
  NSTextField *_manualIP;
  NSButton *_scanButton, *_manualButton;
  NSMutableDictionary<NSString *, NSMutableDictionary *> *_devices;
  NSArray<NSString *> *_orderedAddresses;
  NSMutableArray<NSNetServiceBrowser *> *_browsers;
  NSMutableArray<NSNetService *> *_services;
  NSString *_adbPath, *_target;
  dispatch_queue_t _adbQueue;
  NSInteger _scanID, _connectID;
  BOOL _connected;
  id _keyboardMonitor;
  NSTask *_shellTask;
  NSPipe *_shellInput;
  TouchPadView *_touchPad;
  NSButton *_navTab, *_pointerTab;
  NSTextField *_padHint, *_typeField, *_remoteStatus;
  NSInteger _screenWidth, _screenHeight;
}

- (NSString *)findADB {
  NSMutableArray<NSString *> *locations = [@[@"/opt/homebrew/bin/adb",
    @"/usr/local/bin/adb", @"/usr/bin/adb"] mutableCopy];
  for (NSString *dir in [@(getenv("PATH") ?: "") componentsSeparatedByString:@":"]) {
    [locations addObject:[dir stringByAppendingPathComponent:@"adb"]];
  }
  for (NSString *path in locations)
    if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
  return nil;
}
- (NSString *)runADB:(NSArray<NSString *> *)args timeout:(int)seconds ok:(BOOL *)ok {
  *ok = NO;
  if (!_adbPath) return @"ADB is missing";
  NSTask *task = [NSTask new];
  task.executableURL = [NSURL fileURLWithPath:_adbPath];
  task.arguments = args;
  NSPipe *out = [NSPipe pipe];
  task.standardOutput = out;
  task.standardError = out;
  NSError *error = nil;
  if (![task launchAndReturnError:&error]) return error.localizedDescription ?: @"ADB error";
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  task.terminationHandler = ^(NSTask *finished) {
    (void)finished;
    dispatch_semaphore_signal(done);
  };
  BOOL timeout = dispatch_semaphore_wait(done,
    dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC)) != 0;
  if (timeout && task.isRunning) [task terminate];
  [task waitUntilExit];
  NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
  NSString *response = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  *ok = !timeout && task.terminationStatus == 0;
  return timeout ? @"Connection timed out" :
    [response stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)showRemote:(BOOL)show {
  _discovery.hidden = show;
  _remote.hidden = !show;
  _statusItem.button.title = show && _connected ? @"TV ●" : @"TV";
  _panel.title = show ? @"Remote control" : @"Find your TV";
}

- (void)noteDevice:(NSString *)address name:(NSString *)name
             kind:(NSString *)kind adb:(BOOL)adb {
  NSAssert(NSThread.isMainThread, @"UI updates belong on main thread");
  if (!address.length) return;
  NSMutableDictionary *record = _devices[address];
  if (!record) {
    record = [@{@"address": address, @"name": name.length ? name : @"ADB-capable device",
                @"kind": kind ?: @"Nearby device", @"adb": @(adb)} mutableCopy];
    _devices[address] = record;
  } else {
    if (name.length && ![name isEqualToString:@"Android device"]) record[@"name"] = name;
    if (kind.length) record[@"kind"] = kind;
    if (adb) record[@"adb"] = @YES;
  }
  [self drawDevices];
  if (_scanButton.enabled && _devices.count) {
    NSUInteger count = _devices.count;
    _scanStatus.stringValue = [NSString stringWithFormat:@"%lu possible device%@ found",
      (unsigned long)count, count == 1 ? @"" : @"s"];
    _scanStatus.textColor = Ink(0xA8B9D1);
  }
}

- (void)drawDevices {
  NSArray *keys = [_devices.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    NSDictionary *one = self->_devices[a], *two = self->_devices[b];
    if ([one[@"adb"] boolValue] != [two[@"adb"] boolValue])
      return [one[@"adb"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
    return [a localizedStandardCompare:b];
  }];
  _orderedAddresses = keys;
  for (NSView *subview in [_list.subviews copy]) [subview removeFromSuperview];
  CGFloat rowHeight = 88;
  CGFloat contentHeight = MAX(200, (CGFloat)keys.count * rowHeight);
  [_list setFrameSize:NSMakeSize(342, contentHeight)];
  if (!keys.count) {
    Text(_list, @"No devices detected yet", NSMakeRect(18, 47, 300, 24), 15,
         0xD3DCEE, NSFontWeightSemibold);
    Text(_list, @"Scan or enter your TV's IP below.", NSMakeRect(18, 75, 300, 22),
         12, 0x8EA0BB, NSFontWeightRegular);
    return;
  }
  NSUInteger index = 0;
  for (NSString *address in keys) {
    NSDictionary *record = _devices[address];
    CGFloat y = index * rowHeight + 3;
    NSView *row = [[TopView alloc] initWithFrame:NSMakeRect(0, y, 342, 78)];
    Surface(row, 0x1A293D, 15);
    [_list addSubview:row];
    NSView *tile = [[NSView alloc] initWithFrame:NSMakeRect(12, 16, 44, 46)];
    Surface(tile, 0x2A4163, 12);
    [row addSubview:tile];
    NSImageView *tvIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 11, 24, 24)];
    tvIcon.image = [NSImage imageWithSystemSymbolName:@"tv" accessibilityDescription:@"TV"];
    tvIcon.contentTintColor = Ink(0xAFCEFF);
    [tile addSubview:tvIcon];
    NSString *name = record[@"name"] ?: @"Nearby device";
    Text(row, name, NSMakeRect(68, 12, 160, 22), 14, 0xF8FAFF, NSFontWeightSemibold);
    NSInteger port = [record[@"port"] integerValue];
    NSInteger pairPort = [record[@"pairPort"] integerValue];
    NSString *status = pairPort ? @"Pairing ready" :
      port && port != 5555 ? [NSString stringWithFormat:@"ADB :%ld", (long)port] :
      [record[@"adb"] boolValue] ? @"ADB :5555" : @"Needs ADB";
    NSString *detail = [NSString stringWithFormat:@"%@ · %@",
      address, status];
    Text(row, detail, NSMakeRect(68, 38, 170, 17), 10.5,
         [record[@"adb"] boolValue] || pairPort ? 0x8CDDB9 : 0xA3B4CC, NSFontWeightMedium);
    NSButton *choose = Action(row, pairPort ? @"Pair" : @"Connect",
      NSMakeRect(242, 22, 88, 34),
      [record[@"adb"] boolValue] || pairPort ? 0x366CEC : 0x32435C, 10, 12,
      self, @selector(chooseDevice:), index);
    choose.toolTip = [NSString stringWithFormat:@"Connect to %@", address];
    ++index;
  }
}

- (void)scan:(id)sender {
  (void)sender;
  ++_scanID;
  NSInteger token = _scanID;
  _scanButton.enabled = NO;
  _scanStatus.stringValue = @"Scanning your local network…";
  _scanStatus.textColor = Ink(0x8FB8FF);
  // Keep already discovered services and the saved device on refresh.
  NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"LastTVEndpoint"];
  if (!saved.length) saved = [NSUserDefaults.standardUserDefaults stringForKey:@"LastTVAddress"];
  [_devices removeAllObjects];
  if (saved.length) {
    NSArray<NSString *> *parts = [saved componentsSeparatedByString:@":"];
    NSString *address = parts.firstObject;
    [self noteDevice:address name:@"Previously connected TV" kind:@"Saved" adb:NO];
    if (parts.count == 2) _devices[address][@"port"] = @([parts[1] integerValue]);
  }
  [self drawDevices];
  NSArray<NSString *> *hosts = LANHosts();
  if (!hosts.count) {
    _scanStatus.stringValue = @"No active IPv4 network · check Wi-Fi";
    _scanButton.enabled = YES;
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    dispatch_semaphore_t limit = dispatch_semaphore_create(32);
    dispatch_group_t batch = dispatch_group_create();
    for (NSString *host in hosts) {
      dispatch_semaphore_wait(limit, DISPATCH_TIME_FOREVER);
      dispatch_group_enter(batch);
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (OpenADBPort(host)) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (token == self->_scanID)
              [self noteDevice:host name:nil kind:@"Android / Google TV" adb:YES];
          });
        }
        dispatch_semaphore_signal(limit);
        dispatch_group_leave(batch);
      });
    }
    dispatch_group_wait(batch, DISPATCH_TIME_FOREVER);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (token != self->_scanID) return;
      NSUInteger count = self->_devices.count;
      self->_scanStatus.stringValue = count ?
        [NSString stringWithFormat:@"%lu possible device%@ found", (unsigned long)count,
          count == 1 ? @"" : @"s"] : @"No device found · try an IP address";
      self->_scanStatus.textColor = Ink(0xA8B9D1);
      self->_scanButton.enabled = YES;
    });
  });
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service moreComing:(BOOL)more {
  (void)browser; (void)more;
  [_services addObject:service];
  service.delegate = self;
  [service resolveWithTimeout:3];
}
- (void)netServiceDidResolveAddress:(NSNetService *)service {
  NSString *ip = nil;
  for (NSData *entry in service.addresses) {
    if (entry.length < sizeof(struct sockaddr_in)) continue;
    const struct sockaddr *addr = (const struct sockaddr *)entry.bytes;
    if (addr->sa_family != AF_INET) continue;
    char dotted[INET_ADDRSTRLEN] = {};
    inet_ntop(AF_INET, &((const struct sockaddr_in *)addr)->sin_addr, dotted, sizeof dotted);
    ip = @(dotted);
    break;
  }
  if (ip) {
    NSString *name = service.name;
    if ([name hasPrefix:@"adb-"] || [name hasPrefix:@"adb_"]) name = nil;
    BOOL pairing = [service.type containsString:@"adb-tls-pairing"];
    BOOL connectable = [service.type containsString:@"adb-tls-connect"] ||
                       [service.type containsString:@"_adb._tcp"];
    NSString *kind = [service.type containsString:@"googlecast"] ? @"Google Cast" :
                     [service.type containsString:@"adb"] ? @"ADB advertised" : @"Android TV";
    [self noteDevice:ip name:name kind:kind adb:connectable];
    if (pairing) _devices[ip][@"pairPort"] = @(service.port);
    if (connectable) _devices[ip][@"port"] = @(service.port);
    [self drawDevices];
  }
}
- (void)beginBonjour {
  _browsers = [NSMutableArray array];
  _services = [NSMutableArray array];
  for (NSString *kind in @[@"_googlecast._tcp.", @"_androidtvremote2._tcp.",
                           @"_adb-tls-connect._tcp.", @"_adb-tls-pairing._tcp.",
                           @"_adb._tcp."]) {
    NSNetServiceBrowser *b = [NSNetServiceBrowser new];
    b.delegate = self;
    [_browsers addObject:b];
    [b searchForServicesOfType:kind inDomain:@"local."];
  }
}

- (void)chooseDevice:(NSButton *)sender {
  if (sender.tag < 0 || sender.tag >= (NSInteger)_orderedAddresses.count) return;
  NSString *address = _orderedAddresses[sender.tag];
  NSDictionary *record = _devices[address];
  NSInteger port = [record[@"port"] integerValue];
  NSInteger pairPort = [record[@"pairPort"] integerValue];
  if (pairPort > 0) [self pairAddress:address port:pairPort connectPort:port];
  else [self connectAddress:address port:port > 0 ? port : 5555];
}
- (void)manualConnect:(id)sender {
  (void)sender;
  NSString *input = [_manualIP.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSArray<NSString *> *parts = [input componentsSeparatedByString:@":"];
  NSString *ip = parts.firstObject;
  NSInteger port = parts.count == 2 ? [parts[1] integerValue] : 5555;
  BOOL badPortText = parts.count == 2 &&
    (parts[1].length == 0 ||
     [parts[1] rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound);
  struct in_addr v;
  if (parts.count > 2 || inet_pton(AF_INET, ip.UTF8String, &v) != 1 ||
      port < 1 || port > 65535 || badPortText) {
    _connectStatus.stringValue = @"Enter an IPv4 address (optional :port).";
    return;
  }
  [self connectAddress:ip port:port];
}
- (void)pairAddress:(NSString *)address port:(NSInteger)pairPort connectPort:(NSInteger)port {
  if (!_adbPath) {
    _connectStatus.stringValue = @"Install ADB first: brew install android-platform-tools";
    return;
  }
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"Pair with your TV";
  alert.informativeText = @"On your TV: Developer options → Wireless debugging → Pair device with pairing code. Enter the displayed code.";
  [alert addButtonWithTitle:@"Pair"];
  [alert addButtonWithTitle:@"Cancel"];
  NSTextField *code = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 30)];
  code.placeholderString = @"Pairing code";
  alert.accessoryView = code;
  if ([alert runModal] != NSAlertFirstButtonReturn) return;
  NSString *pin = [code.stringValue stringByTrimmingCharactersInSet:
                                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!pin.length) {
    _connectStatus.stringValue = @"Enter the pairing code shown on your TV.";
    return;
  }
  _connectStatus.stringValue = @"Pairing with your TV…";
  _connectStatus.textColor = Ink(0x9ABFFF);
  NSString *endpoint = [NSString stringWithFormat:@"%@:%ld", address, (long)pairPort];
  dispatch_async(_adbQueue, ^{
    BOOL ok = NO;
    NSString *result = [self runADB:@[@"pair", endpoint, pin] timeout:12 ok:&ok];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!ok) {
        self->_connectStatus.stringValue = @"Pairing failed. Check the code and try again.";
        self->_connectStatus.textColor = Ink(0xFFAEAE);
        NSLog(@"ADB pairing failed: %@", result);
      } else if (port > 0) {
        [self connectAddress:address port:port];
      } else {
        self->_connectStatus.stringValue = @"Paired. Rescan to find the debugging port.";
        self->_connectStatus.textColor = Ink(0x8CDDB9);
      }
    });
  });
}
- (void)connectAddress:(NSString *)address port:(NSInteger)port {
  if (!_adbPath) {
    _connectStatus.stringValue = @"Install ADB first: brew install android-platform-tools";
    return;
  }
  ++_connectID;
  NSInteger token = _connectID;
  _connected = NO;
  _manualButton.enabled = NO;
  _connectStatus.stringValue = [NSString stringWithFormat:@"Connecting to %@…", address];
  _connectStatus.textColor = Ink(0x9ABFFF);
  NSString *target = [NSString stringWithFormat:@"%@:%ld", address, (long)port];
  dispatch_async(_adbQueue, ^{
    BOOL ok = NO;
    NSString *reply = [self runADB:@[@"connect", target] timeout:6 ok:&ok];
    BOOL connected = NO;
    NSString *state = nil;
    if (ok) {
      state = [self runADB:@[@"-s", target, @"get-state"] timeout:4 ok:&ok];
      connected = ok && [state isEqualToString:@"device"];
    }
    NSString *name = @"Android TV", *version = @"";
    NSInteger width = 1920, height = 1080;
    if (connected) {
      BOOL detailOK = NO;
      NSString *model = [self runADB:@[@"-s", target, @"shell", @"getprop",
                                      @"ro.product.model"] timeout:3 ok:&detailOK];
      if (detailOK && model.length) name = model;
      NSString *os = [self runADB:@[@"-s", target, @"shell", @"getprop",
                                    @"ro.build.version.release"] timeout:3 ok:&detailOK];
      if (detailOK && os.length) version = [NSString stringWithFormat:@"Android %@", os];
      NSString *size = [self runADB:@[@"-s", target, @"shell", @"wm", @"size"]
                                timeout:3 ok:&detailOK];
      NSRegularExpression *dimensions = [NSRegularExpression
        regularExpressionWithPattern:@"(\\d+)x(\\d+)" options:0 error:nil];
      NSTextCheckingResult *match = [dimensions firstMatchInString:size options:0
        range:NSMakeRange(0, size.length)];
      if (match) {
        width = [[size substringWithRange:[match rangeAtIndex:1]] integerValue];
        height = [[size substringWithRange:[match rangeAtIndex:2]] integerValue];
      }
    }
    NSString *errorMessage;
    if ([state isEqualToString:@"unauthorized"] ||
        [reply localizedCaseInsensitiveContainsString:@"unauthorized"]) {
      errorMessage = @"Approve debugging on the TV, then reconnect.";
    } else if ([reply localizedCaseInsensitiveContainsString:@"failed to authenticate"]) {
      errorMessage = @"Allow ADB authorization on your TV.";
    } else {
      errorMessage = [reply localizedCaseInsensitiveContainsString:@"No route to host"] ?
        @"TV unreachable. Check its Wi-Fi connection." :
        @"Could not connect. Enable wireless ADB on the TV.";
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (token != self->_connectID) return;
      self->_manualButton.enabled = YES;
      if (!connected) {
        self->_connectStatus.stringValue = errorMessage;
        self->_connectStatus.textColor = Ink(0xFFAEAE);
        return;
      }
      self->_connected = YES;
      self->_target = target;
      self->_screenWidth = width;
      self->_screenHeight = height;
      self->_remoteTitle.stringValue = name;
      self->_remoteDetail.stringValue = version.length ?
        [NSString stringWithFormat:@"%@  ·  %@", address, version] : address;
      [NSUserDefaults.standardUserDefaults setObject:target forKey:@"LastTVEndpoint"];
      self->_connectStatus.stringValue = @"";
      [self noteDevice:address name:name kind:@"Connected" adb:YES];
      [self beginShell:target];
      [self showRemote:YES];
    });
  });
}

- (void)devices:(id)sender {
  (void)sender;
  [self showRemote:NO];
  [self scan:nil];
}
- (void)press:(NSButton *)sender { [self sendKey:sender.tag]; }
- (void)beginShell:(NSString *)target {
  // Called on the main thread. A persistent shell avoids launching adb on
  // every keypress or pointer movement; all writes use the serial ADB queue.
  dispatch_async(_adbQueue, ^{
    if (self->_shellTask.isRunning) [self->_shellTask terminate];
    self->_shellTask = nil;
    self->_shellInput = nil;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:self->_adbPath];
    task.arguments = @[@"-s", target, @"shell"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardInput = pipe;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
      NSLog(@"Could not open low-latency shell: %@", error);
      return; // individual commands still work through adb shell
    }
    self->_shellTask = task;
    self->_shellInput = pipe;
  });
}
- (void)queueCommand:(NSString *)command {
  if (!_connected || !_target || !command.length) return;
  NSString *target = [_target copy];
  NSInteger token = _connectID;
  dispatch_async(_adbQueue, ^{
    BOOL ok = NO;
    NSString *message = @"";
    if (self->_shellTask.isRunning && self->_shellInput) {
      @try {
        NSData *data = [[command stringByAppendingString:@"\n"]
          dataUsingEncoding:NSUTF8StringEncoding];
        [self->_shellInput.fileHandleForWriting writeData:data];
        ok = YES;
      } @catch (NSException *exception) {
        message = exception.reason;
      }
    }
    if (!ok) {
      // If the stream drops, a standalone adb shell can recover it.
      message = [self runADB:@[@"-s", target, @"shell", command] timeout:4 ok:&ok];
    }
    if (!ok) dispatch_async(dispatch_get_main_queue(), ^{
      if (token != self->_connectID) return;
      self->_connected = NO;
      self->_remoteDetail.stringValue = @"Disconnected · choose Devices to reconnect";
      self->_statusItem.button.title = @"TV";
      self->_remoteStatus.stringValue = @"Connection lost. Reconnect from Devices.";
      NSLog(@"ADB command failed: %@", message);
    });
  });
}
- (void)sendKey:(NSInteger)key {
  [self queueCommand:[NSString stringWithFormat:@"input keyevent %ld", (long)key]];
}
- (NSPoint)screenPoint:(NSPoint)pad {
  CGFloat pw = MAX(1, _touchPad.bounds.size.width);
  CGFloat ph = MAX(1, _touchPad.bounds.size.height);
  return NSMakePoint(round(MAX(0, MIN(1, pad.x / pw)) * (_screenWidth - 1)),
                     round(MAX(0, MIN(1, pad.y / ph)) * (_screenHeight - 1)));
}
- (void)padTap:(NSPoint)point {
  NSPoint p = [self screenPoint:point];
  [self queueCommand:[NSString stringWithFormat:@"input touchscreen tap %.0f %.0f", p.x, p.y]];
}
- (void)padSwipe:(NSPoint)start end:(NSPoint)end duration:(NSInteger)duration {
  NSPoint p = [self screenPoint:start], q = [self screenPoint:end];
  [self queueCommand:[NSString stringWithFormat:
    @"input touchscreen swipe %.0f %.0f %.0f %.0f %ld",
    p.x, p.y, q.x, q.y, (long)duration]];
}
- (void)padMove:(NSPoint)point {
  NSPoint p = [self screenPoint:point];
  [self queueCommand:[NSString stringWithFormat:@"input mouse motionevent MOVE %.0f %.0f",
    p.x, p.y]];
}
- (void)changeMode:(NSButton *)button {
  BOOL pointer = button.tag == 1;
  _touchPad.pointerMode = pointer;
  _navTab.layer.backgroundColor = Ink(pointer ? 0x25364E : 0x376BEB).CGColor;
  _pointerTab.layer.backgroundColor = Ink(pointer ? 0x376BEB : 0x25364E).CGColor;
  _padHint.stringValue = pointer ? @"Move to aim · click to tap · drag to swipe" :
    @"Swipe to navigate · click to select · two-finger scroll";
}
- (BOOL)sendText:(NSString *)value {
  if (!value.length || !_connected) return NO;
  // Android's built-in 'input text' handles printable ASCII with %s for space.
  // POSIX single-quote encoding prevents TV-shell command injection.
  for (NSUInteger i = 0; i < value.length; ++i) {
    unichar c = [value characterAtIndex:i];
    if (c != '\n' && c != '\r' && (c < 32 || c > 126)) {
      _remoteStatus.stringValue = @"Only basic Latin characters work with ADB typing.";
      return NO;
    }
  }
  NSMutableString *encoded = [NSMutableString string];
  for (NSUInteger i = 0; i < value.length; ++i) {
    unichar c = [value characterAtIndex:i];
    // A literal '%s' becomes a space in Android's input utility. Emit '%'
    // separately to prevent it merging with the next letter s.
    if (c == '\n' || c == '\r' || c == '%') {
      if (encoded.length) {
        NSString *escaped = [encoded stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        [self queueCommand:[NSString stringWithFormat:@"input text '%@'", escaped]];
        [encoded setString:@""];
      }
      if (c == '%') [self queueCommand:@"input text '%'"]; else [self sendKey:66];
    } else if (c == ' ') {
      [encoded appendString:@"%s"];
    } else {
      [encoded appendFormat:@"%C", c];
    }
  }
  if (encoded.length) {
    NSString *escaped = [encoded stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    [self queueCommand:[NSString stringWithFormat:@"input text '%@'", escaped]];
  }
  return YES;
}
- (void)sendTypedText:(id)sender {
  (void)sender;
  NSString *value = _typeField.stringValue;
  if (!value.length) return;
  if ([self sendText:value]) {
    _typeField.stringValue = @"";
    _remoteStatus.stringValue = @"Text sent to active TV field";
  }
}
- (void)togglePanel:(id)sender {
  (void)sender;
  if (_panel.isVisible) [_panel orderOut:nil];
  else { [_panel makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
}
- (void)windowWillClose:(NSNotification *)note { (void)note; [_panel orderOut:nil]; }
- (void)quit:(id)sender { [NSApp terminate:sender]; }

- (void)buildDiscovery {
  _discovery = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
  [_panel.contentView addSubview:_discovery];
  Text(_discovery, @"Find your TV", Frame(24, 49, 270, 39), 29,
       0xF4F7FF, NSFontWeightBold);
  Action(_discovery, @"Quit", Frame(309, 51, 57, 34), 0x563442, 10, 12,
         self, @selector(quit:), 0);
  Text(_discovery, @"Connect to Android TV or Google TV nearby.",
       Frame(24, 97, 343, 22), 13, 0xA5B4CB, NSFontWeightRegular);
  NSView *network = [[TopView alloc] initWithFrame:Frame(24, 140, 342, 62)];
  Surface(network, 0x1B2A41, 14);
  [_discovery addSubview:network];
  Icon(network, @"wifi", @"Local network", NSMakeRect(14, 13, 36, 36),
       0x2C466A, 10, 18, nil, NULL, 0).enabled = NO;
  Text(network, @"Local network", NSMakeRect(62, 12, 205, 23), 14,
       0xF4F7FF, NSFontWeightSemibold);
  _scanStatus = Text(network, @"Ready to scan", NSMakeRect(62, 34, 218, 18),
                     11, 0xA5B4CB, NSFontWeightRegular);
  _scanButton = Icon(network, @"arrow.clockwise", @"Scan again",
                     NSMakeRect(294, 12, 36, 38), 0x314B70, 10, 16,
                     self, @selector(scan:), 0);

  Text(_discovery, @"Available devices", Frame(24, 220, 230, 25), 16,
       0xF4F7FF, NSFontWeightSemibold);
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:Frame(24, 256, 342, 224)];
  scroll.drawsBackground = NO;
  scroll.borderType = NSNoBorder;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  _list = [[TopView alloc] initWithFrame:NSMakeRect(0, 0, 342, 224)];
  scroll.documentView = _list;
  [_discovery addSubview:scroll];
  _devices = [NSMutableDictionary dictionary];
  [self drawDevices];

  Text(_discovery, @"Connect with IP address", Frame(24, 497, 290, 22), 14,
       0xE9F0FD, NSFontWeightSemibold);
  NSView *inputShell = [[TopView alloc] initWithFrame:Frame(24, 529, 230, 42)];
  Surface(inputShell, 0x1A293D, 10);
  [_discovery addSubview:inputShell];
  _manualIP = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 10, 206, 24)];
  _manualIP.placeholderAttributedString = [[NSAttributedString alloc]
    initWithString:@"e.g. 192.168.1.100"
    attributes:@{NSForegroundColorAttributeName: Ink(0x8195B2)}];
  _manualIP.stringValue = [NSUserDefaults.standardUserDefaults
                            stringForKey:@"LastTVEndpoint"] ?:
                          [NSUserDefaults.standardUserDefaults
                            stringForKey:@"LastTVAddress"] ?: @"";
  _manualIP.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightMedium];
  _manualIP.textColor = Ink(0xF8FAFF);
  _manualIP.backgroundColor = NSColor.clearColor;
  _manualIP.bordered = NO;
  _manualIP.bezeled = NO;
  _manualIP.drawsBackground = NO;
  [inputShell addSubview:_manualIP];
  _manualButton = Action(_discovery, @"Connect", Frame(262, 529, 104, 42),
                         0x366CEC, 11, 13, self, @selector(manualConnect:), 0);
  _connectStatus = Text(_discovery, @"ADB access is required to control a TV.",
                        Frame(24, 581, 342, 20), 11, 0x93A8C6, NSFontWeightRegular);
}

- (void)buildRemote {
  _remote = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
  [_panel.contentView addSubview:_remote];
  _remote.hidden = YES;
  Icon(_remote, @"chevron.left", @"Back to devices", Frame(24, 43, 40, 40),
       0x22334C, 11, 15, self, @selector(devices:), 0);
  Text(_remote, @"Remote", Frame(78, 47, 138, 32), 23,
       0xF8FAFF, NSFontWeightBold);
  Action(_remote, @"Devices", Frame(220, 46, 85, 34), 0x22334C, 11, 12,
         self, @selector(devices:), 0);
  Action(_remote, @"Quit", Frame(313, 46, 53, 34), 0x563442, 10, 12,
         self, @selector(quit:), 0);
  NSView *connectedPill = [[TopView alloc] initWithFrame:Frame(24, 94, 342, 60)];
  Surface(connectedPill, 0x1A293D, 14);
  [_remote addSubview:connectedPill];
  NSView *dot = [[NSView alloc] initWithFrame:NSMakeRect(16, 24, 9, 9)];
  Surface(dot, 0x5CE3AA, 5);
  [connectedPill addSubview:dot];
  _remoteTitle = Text(connectedPill, @"Android TV", NSMakeRect(35, 7, 280, 25),
                      15, 0xF4F7FF, NSFontWeightSemibold);
  _remoteDetail = Text(connectedPill, @"Connected", NSMakeRect(35, 33, 280, 18),
                       11, 0xA7B9D4, NSFontWeightRegular);

  _navTab = Action(_remote, @"Trackpad", Frame(24, 168, 167, 35),
    0x376BEB, 10, 13, self, @selector(changeMode:), 0);
  _pointerTab = Action(_remote, @"Pointer", Frame(199, 168, 167, 35),
    0x25364E, 10, 13, self, @selector(changeMode:), 1);

  _touchPad = [[TouchPadView alloc] initWithFrame:Frame(24, 215, 342, 176)];
  Surface(_touchPad, 0x1D304B, 18);
  _touchPad.toolTip = @"Swipe to navigate or click to select";
  _touchPad.accessibilityLabel = @"TV trackpad: swipe to navigate, click to select";
  [_remote addSubview:_touchPad];
  NSView *mark = [[TopView alloc] initWithFrame:NSMakeRect(134, 40, 74, 74)];
  Surface(mark, 0x2D4870, 37);
  [_touchPad addSubview:mark];
  NSImageView *gesture = [[NSImageView alloc] initWithFrame:NSMakeRect(22, 21, 30, 30)];
  gesture.image = [NSImage imageWithSystemSymbolName:@"hand.point.up.left"
                            accessibilityDescription:@"Touchpad"];
  gesture.contentTintColor = Ink(0xBDD4FF);
  [mark addSubview:gesture];
  Text(_touchPad, @"SWIPE  ·  CLICK  ·  SCROLL", NSMakeRect(61, 137, 230, 18),
       10, 0x88A8D1, NSFontWeightSemibold).alignment = NSTextAlignmentCenter;
  __weak RemoteAppDelegate *weakSelf = self;
  _touchPad.onStep = ^(NSInteger key) { [weakSelf sendKey:key]; };
  _touchPad.onTap = ^(NSPoint p) { [weakSelf padTap:p]; };
  _touchPad.onSwipe = ^(NSPoint a, NSPoint b, NSInteger ms) {
    [weakSelf padSwipe:a end:b duration:ms];
  };
  _touchPad.onMove = ^(NSPoint p) { [weakSelf padMove:p]; };
  _padHint = Text(_remote, @"Swipe to navigate · click to select · two-finger scroll",
    Frame(24, 396, 342, 22), 11, 0xA4B8D5, NSFontWeightRegular);
  _padHint.alignment = NSTextAlignmentCenter;

  Icon(_remote, @"arrow.uturn.backward", @"Back", Frame(24, 427, 78, 43),
    0x22364F, 11, 19, self, @selector(press:), 4);
  Icon(_remote, @"house", @"Home", Frame(111, 427, 78, 43),
    0x22364F, 11, 19, self, @selector(press:), 3);
  Icon(_remote, @"speaker.slash", @"Mute or unmute", Frame(198, 427, 78, 43),
    0x365783, 11, 19, self, @selector(press:), 164);
  Icon(_remote, @"line.3.horizontal", @"Menu", Frame(285, 427, 81, 43),
    0x22364F, 11, 19, self, @selector(press:), 82);

  Icon(_remote, @"speaker.minus", @"Volume down", Frame(24, 479, 78, 43),
    0x22364F, 11, 19, self, @selector(press:), 25);
  Icon(_remote, @"speaker.plus", @"Volume up", Frame(111, 479, 78, 43),
    0x22364F, 11, 19, self, @selector(press:), 24);
  Icon(_remote, @"playpause", @"Play or pause", Frame(198, 479, 78, 43),
    0x22364F, 11, 19, self, @selector(press:), 85);
  Icon(_remote, @"power", @"Power", Frame(285, 479, 81, 43),
    0x563442, 11, 19, self, @selector(press:), 26);

  NSView *textShell = [[TopView alloc] initWithFrame:Frame(24, 535, 266, 39)];
  Surface(textShell, 0x24354C, 10);
  [_remote addSubview:textShell];
  _typeField = [[NSTextField alloc] initWithFrame:NSMakeRect(13, 10, 244, 21)];
  _typeField.placeholderString = @"Type or paste text for TV…";
  _typeField.font = [NSFont systemFontOfSize:13];
  _typeField.textColor = Ink(0xF4F7FF);
  _typeField.backgroundColor = NSColor.clearColor;
  _typeField.bordered = NO;
  _typeField.bezeled = NO;
  _typeField.focusRingType = NSFocusRingTypeNone;
  _typeField.target = self;
  _typeField.action = @selector(sendTypedText:);
  [textShell addSubview:_typeField];
  Action(_remote, @"Send", Frame(298, 535, 68, 39), 0x376BEB, 10, 12,
    self, @selector(sendTypedText:), 0);
  _remoteStatus = Text(_remote, @"Arrows · Return · Esc · ⌘M mute · ⌘⇧V paste",
    Frame(24, 580, 342, 18), 10, 0x91A9C8, NSFontWeightRegular);
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  (void)note;
  _adbQueue = dispatch_queue_create("tv.remote.adb", DISPATCH_QUEUE_SERIAL);
  _adbPath = [self findADB];
  _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
  _statusItem.button.title = @"TV";
  _statusItem.button.toolTip = @"Android TV Remote";
  _statusItem.button.target = self;
  _statusItem.button.action = @selector(togglePanel:);

  NSRect screen = NSScreen.mainScreen.visibleFrame;
  _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(NSMidX(screen) - W / 2,
         NSMidY(screen) - H / 2, W, H)
         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                   NSWindowStyleMaskFullSizeContentView
         backing:NSBackingStoreBuffered defer:NO];
  _panel.title = @"Find your TV";
  _panel.titleVisibility = NSWindowTitleHidden;
  _panel.titlebarAppearsTransparent = YES;
  // Background dragging competes with touchpad swipes and shifts the window.
  _panel.movableByWindowBackground = NO;
  _panel.floatingPanel = YES;
  _panel.hidesOnDeactivate = NO;
  _panel.level = NSFloatingWindowLevel;
  _panel.delegate = self;
  _panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
  Surface(_panel.contentView, 0x101A2B, 16);
  [self buildDiscovery];
  [self buildRemote];

  __weak RemoteAppDelegate *weakSelf = self;
  _keyboardMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
    handler:^NSEvent *(NSEvent *event) {
      RemoteAppDelegate *owner = weakSelf;
      if (!owner || owner->_remote.hidden || !owner->_panel.isKeyWindow) return event;
      if ([owner->_panel.firstResponder isKindOfClass:NSTextView.class]) return event;
      if ((event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) ==
          (NSEventModifierFlagCommand | NSEventModifierFlagShift) && event.keyCode == 9) {
        [owner sendText:[NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString] ?: @""];
        return nil;
      }
      if ((event.modifierFlags & NSEventModifierFlagCommand) &&
          !(event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption)) &&
          event.keyCode == 46) {
        [owner sendKey:164]; // Command-M: TV mute
        return nil;
      }
      if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                                  NSEventModifierFlagOption)) return event;
      NSInteger key = -1;
      switch (event.keyCode) {
        case 126: key = 19; break;
        case 125: key = 20; break;
        case 123: key = 21; break;
        case 124: key = 22; break;
        case 36: case 76: key = 23; break;
        case 53: key = 4; break;
        case 49: key = 85; break;
        case 51: key = 67; break;
        case 48: key = 61; break;
      }
      if (key >= 0) [owner sendKey:key];
      else if (event.characters.length) {
        [owner sendText:event.characters];
      } else return event;
      return nil;
    }];

  [_panel makeKeyAndOrderFront:nil];
  [_panel makeFirstResponder:nil];
  [NSApp activateIgnoringOtherApps:YES];
  if (!_adbPath) {
    _connectStatus.stringValue = @"ADB missing · brew install android-platform-tools";
    _connectStatus.textColor = Ink(0xFFAEAE);
  }
  [self beginBonjour];
  [self scan:nil];
}
@end
int main(void) {
  @autoreleasepool {
    NSApplication *app = NSApplication.sharedApplication;
    RemoteAppDelegate *delegate = [RemoteAppDelegate new];
    app.delegate = delegate;
    [app run];
  }
  return 0;
}
