/*
 * Copyright 2011 Jason Rush and John Flanagan. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import "MiniKeePassAppDelegate.h"
#import "SFHFKeychainUtils.h"
#import "LockScreenController.h"

#define DURATION 0.3

@implementation LockScreenController

static NSInteger timeoutValues[] = {0, 30, 60, 120, 300};
static NSInteger deleteOnFailureAttemptsValues[] = {3, 5, 10, 15};

- (id)init {
    self = [super init];
    if (self) {

        visibleFrame = CGRectZero;
        offScreenFrame = CGRectOffset(visibleFrame, 0, -95);
        
        pinViewController = [[PinViewController alloc] init];
        pinViewController.delegate = self;
        pinViewController.view.frame = offScreenFrame;
        [self.view addSubview:pinViewController.view];
        
        self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"splash"]];
        
        appDelegate = (MiniKeePassAppDelegate*)[[UIApplication sharedApplication] delegate];
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        [notificationCenter addObserver:self 
                               selector:@selector(applicationDidBecomeActive:)
                                   name:UIApplicationDidBecomeActiveNotification
                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [pinViewController release];
    [super dealloc];
}

- (UIViewController *)frontMostViewController {
    UIViewController *frontViewController = appDelegate.window.rootViewController;
    while (frontViewController.modalViewController != nil) {
        frontViewController = frontViewController.modalViewController;
    }
    return frontViewController;
}

- (void)show {
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"splash"]];
    [[self frontMostViewController] presentModalViewController:self animated:NO];
}

+ (void)present {
    LockScreenController *pinScreen = [[LockScreenController alloc] init];
    [pinScreen show];
    [pinScreen release];
}

- (void)hide {
    [self dismissModalViewControllerAnimated:NO];
}

- (void)lock {
    appDelegate.locked = YES;

    pinViewController.textLabel.text = NSLocalizedString(@"Enter your PIN to unlock", nil);
    
    [pinViewController becomeFirstResponder];
    [UIView animateWithDuration:DURATION animations:^{
        pinViewController.view.frame = visibleFrame;
    }];
}

- (void)unlock {
    appDelegate.locked = NO;
    
    [UIView animateWithDuration:DURATION
                     animations:^{
                         pinViewController.view.frame = offScreenFrame;
                         [pinViewController resignFirstResponder];
                     }
                     completion:^(BOOL finished){
                         [self hide];
                     }];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Get the time when the application last exited
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDate *exitTime = [userDefaults valueForKey:@"exitTime"];
    
    // Check if the PIN is enabled
    if ([userDefaults boolForKey:@"pinEnabled"] && exitTime != nil) {
        // Get the lock timeout (in seconds)
        NSInteger pinLockTimeout = timeoutValues[[userDefaults integerForKey:@"pinLockTimeout"]];
        
        // Check if it's been longer then lock timeout
        NSTimeInterval timeInterval = -[exitTime timeIntervalSinceNow];
        if (timeInterval > pinLockTimeout) {
            [self lock];
        } else {
            [self unlock];
        }
    } else {
        [self unlock];
    }
}

- (void)pinViewController:(PinViewController *)controller pinEntered:(NSString *)pin {
    NSString *validPin = [SFHFKeychainUtils getPasswordForUsername:@"PIN" andServiceName:@"com.jflan.MiniKeePass.pin" error:nil];
    if (validPin == nil) {
        // Delete all data
        [appDelegate deleteAllData];
        
        // Hide spashscreen
        [self unlock];
    } else {
        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
        
        // Check if the PIN is valid
        if ([pin isEqualToString:validPin]) {
            // Reset the number of pin failed attempts
            [userDefaults setInteger:0 forKey:@"pinFailedAttempts"];
            
            // Dismiss the pin view
            [self unlock];
        } else {
            // Vibrate to signify they are a bad user
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
            [controller clearEntry];
            
            if (![userDefaults boolForKey:@"deleteOnFailureEnabled"]) {
                // Update the status message on the PIN view
                controller.textLabel.text = NSLocalizedString(@"Incorrect PIN", nil);
            } else {
                // Get the number of failed attempts
                NSInteger pinFailedAttempts = [userDefaults integerForKey:@"pinFailedAttempts"];
                [userDefaults setInteger:++pinFailedAttempts forKey:@"pinFailedAttempts"];
                
                // Get the number of failed attempts before deleting
                NSInteger deleteOnFailureAttempts = deleteOnFailureAttemptsValues[[userDefaults integerForKey:@"deleteOnFailureAttempts"]];
                
                // Update the status message on the PIN view
                NSInteger remainingAttempts = (deleteOnFailureAttempts - pinFailedAttempts);
                controller.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Incorrect PIN\n%d attempt%@ remaining", nil), remainingAttempts, remainingAttempts > 1 ? @"s" : @""];
                
                // Check if they have failed too many times
                if (pinFailedAttempts >= deleteOnFailureAttempts) {
                    // Delete all data
                    [appDelegate deleteAllData];
                    
                    // Dismiss the pin view
                    [self unlock];
                }
            }
        }
    }
}

@end
