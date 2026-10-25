#ifndef FOCUS_LINK_DARWIN_TRAY_H
#define FOCUS_LINK_DARWIN_TRAY_H

void FocusLinkInstallStatusItem(const void *iconData, int iconLength);
void FocusLinkPresentPopover(void);
void FocusLinkClosePopover(void);
void FocusLinkDispatchPopoverAction(const char *action, const char *name);
void FocusLinkDispatchOpenPage(const char *page);
void FocusLinkDispatchQuit(void);
void FocusLinkUpdatePopover(const char *stateJSON);
void FocusLinkSetPopoverBusy(int busy);

#endif
