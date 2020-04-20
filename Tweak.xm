#include "Tweak.h"

/**
 * Load Preferences
 */
BOOL noads;
BOOL disablereadreceipt;
BOOL disabletypingindicator;
BOOL disablestoryseenreceipt;
BOOL cansavefriendsstory;
BOOL hidesearchbar;
BOOL hidestoriesrow;
BOOL hidepeopletab;

static void reloadPrefs() {
  NSDictionary *settings = [[NSMutableDictionary alloc] initWithContentsOfFile:@PLIST_PATH];

  noads = [[settings objectForKey:@"noads"] ?: @(YES) boolValue];
  disablereadreceipt = [[settings objectForKey:@"disablereadreceipt"] ?: @(YES) boolValue];
  disabletypingindicator = [[settings objectForKey:@"disabletypingindicator"] ?: @(YES) boolValue];
  disablestoryseenreceipt = [[settings objectForKey:@"disablestoryseenreceipt"] ?: @(YES) boolValue];
  cansavefriendsstory = [[settings objectForKey:@"cansavefriendsstory"] ?: @(YES) boolValue];
  hidesearchbar = [[settings objectForKey:@"hidesearchbar"] ?: @(NO) boolValue];
  hidestoriesrow = [[settings objectForKey:@"hidestoriesrow"] ?: @(NO) boolValue];
  hidepeopletab = [[settings objectForKey:@"hidepeopletab"] ?: @(NO) boolValue];
}
static void PreferencesChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
  reloadPrefs();
}


/**
 * Tweak's hooking code
 */
%group NoAdsNoStoriesRow
  %hook MSGThreadListDataSource
    - (NSArray *)inboxRows {
      NSArray *orig = %orig;
      if (![orig count]) {
        return orig;
      }

      NSMutableArray *resultRows = [@[] mutableCopy];

      if (!(hidestoriesrow && [orig[0][2] isKindOfClass:[NSArray class]] && [orig[0][2][1] isEqual:@"montage_renderer"])) {
        [resultRows addObject:orig[0]];
      }

      for (int i = 1; i < [orig count]; i++) {
        NSArray *row = orig[i];
        if (!noads || (noads && [row[1] intValue] != 2)) {
          [resultRows addObject:row];
        }
      }

      return resultRows;
    }
  %end
%end

%group DisableReadReceipt
  %hook LSMessageListViewController
    - (void)_sendReadReceiptIfNeeded {
      if (!disablereadreceipt) {
        %orig;
      }
    }
  %end
%end

%group DisableTypingIndicator
  %hook LSComposerViewController
    - (void)_updateComposerEventWithTextViewChanged:(id)arg1 {
      if (!disabletypingindicator) {
        %orig;
      }
    }
  %end
%end

%group DisableStorySeenReceipt
  %hook LSStoryBucketViewController
    - (void)startTimer {
      if (!disablestoryseenreceipt) {
        %orig;
      }
    }
  %end
%end

%group CanSaveFriendsStory
  %hook LSAppDelegate
    static LSAppDelegate *__weak sharedInstance;
    - (void)applicationDidBecomeActive:(id)arg1 {
      %orig;
      sharedInstance = self;
    }

    %new
    + (id)sharedInstance {
      return sharedInstance;
    }
  %end

  %hook LSStoryOverlayProfileView
    - (void)_handleOverflowMenuButton:(UIButton *)arg1 {
      // check if this story is mine
      MBUIStoryViewerAuthorOverlayModel *_authorOverlayModel = MSHookIvar<MBUIStoryViewerAuthorOverlayModel *>(self, "_authorOverlayModel");
      if ([_authorOverlayModel.authorId isEqual:[[%c(LSAppDelegate) sharedInstance] getCurrentLoggedInUserId]]) {
        %orig;
        return;
      }

      // otherwise show alert with save and original actions
      LSStoryOverlayViewController * overlayVC = (LSStoryOverlayViewController *)[[[self nextResponder] nextResponder] nextResponder];
      LSStoryBucketViewController * bucketVC = overlayVC.parentViewController;
      [bucketVC _pauseProgressIndicatorWithReset:FALSE];

      UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
      UIAlertAction *saveStoryAction = [UIAlertAction actionWithTitle:@"Save Story" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        LSMediaViewController * mediaVC = bucketVC.currentThreadVC;
        [mediaVC saveMedia];
      }];
      UIAlertAction *otherOptionsAction = [UIAlertAction actionWithTitle:@"Options" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        %orig;
      }];
      UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        [bucketVC startTimer];
      }];
      [alert addAction:saveStoryAction];
      [alert addAction:otherOptionsAction];
      [alert addAction:cancelAction];

      if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
        [alert setModalPresentationStyle:UIModalPresentationPopover];
        UIPopoverPresentationController *popPresenter = [alert popoverPresentationController];
        popPresenter.sourceView = arg1;
        popPresenter.sourceRect = arg1.bounds;
      }
      [overlayVC presentViewController:alert animated:YES completion:nil];
    }
  %end
%end

%group HidePeopleTab
  %hook UITabBarController
    - (UITabBar *)tabBar {
      UITabBar *orig = %orig;
      orig.hidden = true;
      return orig;
    }
  %end
%end

%group HideSearchBar
  %hook UINavigationController
    - (void)_createAndAttachSearchPaletteForTransitionToTopViewControllerIfNecesssary:(id)arg1 {
    }
  %end
%end


/**
 * Constructor
 */
%ctor {
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback) PreferencesChangedCallback, CFSTR(PREF_CHANGED_NOTIF), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
  reloadPrefs();

  dlopen([[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/NotInCore.framework/NotInCore"] UTF8String], RTLD_NOW);

  %init(NoAdsNoStoriesRow);
  %init(DisableReadReceipt);
  %init(DisableTypingIndicator);
  %init(DisableStorySeenReceipt);
  %init(CanSaveFriendsStory);

  if (hidesearchbar) {
    %init(HideSearchBar);
  }

  if (hidepeopletab) {
    %init(HidePeopleTab);
  }
}

