#ifndef FOCUS_LINK_DARWIN_TRAY_H
#define FOCUS_LINK_DARWIN_TRAY_H

void FocusLinkInstallStatusItem(void);
void FocusLinkPresentPopover(void);
void FocusLinkClosePopover(void);
void FocusLinkUpdatePopover(const char *stateJSON);
void FocusLinkSetPopoverBusy(int busy);

#endif
