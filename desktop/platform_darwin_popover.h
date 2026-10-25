#ifndef FOCUS_LINK_DARWIN_POPOVER_H
#define FOCUS_LINK_DARWIN_POPOVER_H

#import <AppKit/AppKit.h>

@interface FocusLinkPopoverViewController : NSViewController
- (void)updateWithState:(NSDictionary *)state;
- (void)setBusy:(BOOL)busy;
@end

void FocusLinkConfigureStatusPanel(NSPanel *panel);
void FocusLinkUpdatePopover(const char *stateJSON);
void FocusLinkSetPopoverBusy(int busy);

#endif
