//
//  CLIPAppDelegate.m
//  Clippy
//
//  Created by Tim Johnsen on 7/31/14.
//  Copyright (c) 2014 tijo. All rights reserved.
//

#import "CLIPAppDelegate.h"
#import "CLIPPasteboardPoller.h"
#import <Dropbox/Dropbox.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "CLIPViewController.h"

@interface CLIPAlertView : UIAlertView

@property (nonatomic, strong) UIImage *image;

@end

@implementation CLIPAlertView

@end

@interface CLIPAppDelegate () <CLIPPasteboardPollerDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) CLIPPasteboardPoller *poller;
@property (nonatomic, assign) UIBackgroundTaskIdentifier taskIdentifier;

@property (nonatomic, strong) DBAccountManager *accountManager;
@property (nonatomic, strong) DBFilesystem *filesystem;

@property (nonatomic, copy) NSString *lastWrittenFilename;

@property (nonatomic, strong) CLIPViewController *mainViewController;

@property (nonatomic, copy) NSString *lastUpdateSource;
@property (nonatomic, copy) NSDate *lastUpdateDate;

@end

@implementation CLIPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor whiteColor];
    [self.window makeKeyAndVisible];
    
    self.mainViewController = [[CLIPViewController alloc] init];
    self.window.rootViewController = self.mainViewController;
    
    self.accountManager = [[DBAccountManager alloc] initWithAppKey:@"<DROPBOX-KEY>" secret:@"<DROPBOX-SECRET>"];
    [DBAccountManager setSharedManager:self.accountManager];
    
    if ([[DBAccountManager sharedManager] linkedAccount]) {
        [self setupObserver];
    } else {
        [[DBAccountManager sharedManager] linkFromController:self.window.rootViewController];
    }
    
    // Keep alive
    self.taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:self.taskIdentifier];
        self.taskIdentifier = UIBackgroundTaskInvalid;
    }];
    
    self.poller = [[CLIPPasteboardPoller alloc] init];
    self.poller.delegate = self;
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateInfoText) userInfo:nil repeats:YES];
    
    [self setupAssetLibraryObserver];
    
    return YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    NSData *imageData = [[notification userInfo] objectForKey:@"image"];
    UIImage *image = [UIImage imageWithData:imageData];
    if (image) {
        [self saveImage:image];
    }
}

- (void)saveImage:(UIImage *)image
{
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (!error) {
        [[[UIAlertView alloc] initWithTitle:@"Image Saved" message:@"A copied image was saved to your device" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"A copied image was not saved to your device" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}

- (void)pasteboardDidChange
{
    NSLog(@"CHANGE");
    
//    NSDictionary *item = [[[UIPasteboard generalPasteboard] items] firstObject];
//    
//    NSString *type = [[item allKeys] firstObject];
//    id<NSCoding> value = [item objectForKey:type];
//    
//    NSString *filename = [NSString stringWithFormat:@"%f-%@", [NSDate timeIntervalSinceReferenceDate], [[type dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
//    
//    self.lastWrittenFilename = filename;
//    
//    DBPath *newPath = [[DBPath root] childPath:filename];
//    DBFile *file = [[DBFilesystem sharedFilesystem] createFile:newPath error:nil];
//    [file writeData:[NSKeyedArchiver archivedDataWithRootObject:value] error:nil];
    
    NSMutableDictionary *encodedPasteboardContents = [[NSMutableDictionary alloc] init];
    
    [encodedPasteboardContents setValue:[[UIPasteboard generalPasteboard] string] forKey:@"string"];
    
    UIImage *image = [[UIPasteboard generalPasteboard] image];
    const CGFloat maxDimension = 640.0;
    if (image) {
        CGFloat scale = 0.0;
        if (image.size.width > image.size.height) {
            scale = maxDimension / image.size.width;
        } else {
            scale = maxDimension / image.size.height;
        }
        
        if (scale < 1.0) {
            image = [UIImage imageWithCGImage:image.CGImage scale:1.0 / scale orientation:image.imageOrientation];
        }
    }
    
    [encodedPasteboardContents setValue:UIImageJPEGRepresentation(image, 0.5) forKey:@"image"]; // todo handle encoding
    
    [encodedPasteboardContents setValue:[[[UIPasteboard generalPasteboard] URL] absoluteString] forKey:@"url"];
    
    NSString *filename = [NSString stringWithFormat:@"%f", [NSDate timeIntervalSinceReferenceDate]];

    self.lastWrittenFilename = filename;

    DBPath *newPath = [[DBPath root] childPath:filename];
    DBFile *file = [[DBFilesystem sharedFilesystem] createFile:newPath error:nil];
    [file writeData:[NSPropertyListSerialization dataFromPropertyList:encodedPasteboardContents format:NSPropertyListBinaryFormat_v1_0 errorDescription:nil] error:nil];
    [file close];
    
    self.lastUpdateSource = @"locally";
    self.lastUpdateDate = [NSDate date];
}

- (void)setupObserver
{
    DBAccount *account = [[DBAccountManager sharedManager] linkedAccount];
    self.filesystem = [[DBFilesystem alloc] initWithAccount:account];
    [DBFilesystem setSharedFilesystem:self.filesystem];
    
    [[DBFilesystem sharedFilesystem] addObserver:self forPathAndChildren:[DBPath root] block:^{
        // Get most recent file info
        if ([[DBFilesystem sharedFilesystem] completedFirstSync] && [[DBFilesystem sharedFilesystem] status].anyInProgress == NO) {
            DBFileInfo *mostRecentFile = nil;
            for (DBFileInfo *fileInfo in [[DBFilesystem sharedFilesystem] listFolder:[DBPath root] error:nil]) {
                if (!mostRecentFile || [fileInfo.modifiedTime compare:mostRecentFile.modifiedTime] == NSOrderedDescending) {
                    mostRecentFile = fileInfo;
                }
            }
            
            if (mostRecentFile && ![[[mostRecentFile path] name] isEqualToString:self.lastWrittenFilename]) {
                
                NSLog(@"Add");
                
                DBFile *file = [[DBFilesystem sharedFilesystem] openFile:mostRecentFile.path error:nil];
                DBFileStatus *status = file.status;
                if (!status.cached) {
                    NSLog(@"Not cached 1");
                    [file addObserver:self block:^{
                        if (file.status.cached) {
                            NSLog(@"Cached");
                            DBError *err = nil;
                            [file update:&err];
                            if (err) {
                                NSLog(@"Err %@", err);
                            }
                            
                            NSData *data = [file readData:nil];
                            NSLog(@"%zu", [data length]);
                            
                            if ([data length] > 0) {
                                NSDictionary *pasteboard = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
                                
                                NSString *pasteboardString = [pasteboard objectForKey:@"string"];
                                NSData *pasteboardImageData = [pasteboard objectForKey:@"image"];
                                NSString *pasteboardURL = [pasteboard objectForKey:@"url"];
                                
                                self.poller.suppressChangeEvents = YES;
                                
//                                if (pasteboardString || pasteboardImageData || pasteboardURL) {
//                                    [[NSPasteboard generalPasteboard] clearContents];
//                                }
                                
                                if (pasteboardString) {
                                    [[UIPasteboard generalPasteboard] setString:pasteboardString];
                                    NSLog(@"Set string");
                                }
                                
                                if (pasteboardImageData) {
                                    [[UIPasteboard generalPasteboard] setImage:[UIImage imageWithData:pasteboardImageData]];
                                    NSLog(@"Set image");
                                    
                                    // Local notification...
                                    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
                                        [[UIApplication sharedApplication] cancelAllLocalNotifications];
                                        
                                        UILocalNotification *l = [[UILocalNotification alloc] init];
                                        [l setAlertBody:@"Save pasteboard image to photos?"];
                                        [l setAlertAction:@"save"];
                                        [l setUserInfo:@{@"image" : pasteboardImageData}];
                                        [[UIApplication sharedApplication] scheduleLocalNotification:l];
                                    } else {
                                        
                                        CLIPAlertView *alert = [[CLIPAlertView alloc] initWithTitle:@"Save pasteboard image to photos?" message:nil delegate:self cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
                                        [alert setImage:[UIImage imageWithData:pasteboardImageData]];
                                        [alert setDelegate:self];
                                        [alert show];
                                    }
                                }
                                
                                if (pasteboardURL) {
                                    NSURL *url = [NSURL URLWithString:pasteboardURL];
                                    if (url) {
                                        [[UIPasteboard generalPasteboard] setURL:url];
                                        NSLog(@"Set URL");
                                    }
                                }
                                
                                self.lastUpdateSource = @"remotely";
                                self.lastUpdateDate = [NSDate date];
                                
                                self.poller.suppressChangeEvents = NO;
                                
                                [file removeObserver:self];
                            }
                            
                        } else {
                            NSLog(@"Not cached");
                        }
                    }];
                } else {
                    NSLog(@"Cached");
                }
            }
        }
    }];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    DBAccount *account = [[DBAccountManager sharedManager] handleOpenURL:url];
    BOOL handled = NO;
    
    if (account) {
        handled = YES;
        [self setupObserver];
    }
    return handled;
}

- (void)updateInfoText
{
    if (self.lastUpdateDate && self.lastUpdateSource) {
        NSUInteger t = fabs([self.lastUpdateDate timeIntervalSinceNow]);
        NSString *timeString = nil;
        if (t < 60) {
            // seconds
            NSUInteger val = t;
            timeString = [NSString stringWithFormat:@"%zd second%@ ago", t, val != 1 ? @"s" : @""];
        } else if (t < 3600) {
            // minutes
            NSUInteger val = t / 60;
            timeString = [NSString stringWithFormat:@"%zd minute%@ ago", val, val != 1 ? @"s" : @""];
        } else if (t < 86400) {
            // hours
            NSUInteger val = t / 3600;
            timeString = [NSString stringWithFormat:@"%zd hour%@ ago", val, val != 1 ? @"s" : @""];
        } else if (t < 86400 * 7) {
            // days
            NSUInteger val = t / 86400;
            timeString = [NSString stringWithFormat:@"%zd day%@ ago", val, val != 1 ? @"s" : @""];
        } else {
            timeString = @"a long time ago";
        }
        self.mainViewController.infoLabel.text = [NSString stringWithFormat:@"Last updated %@ %@", self.lastUpdateSource, timeString];
    } else {
        self.mainViewController.infoLabel.text = @"Idle";
    }
}

- (void)setupAssetLibraryObserver
{
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(pollAssetLibrary) userInfo:nil repeats:YES];
}
  
- (void)pollAssetLibrary
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    static NSInteger numberOfAssets = 0;
    
    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *ostop) {
        [group setAssetsFilter:[ALAssetsFilter allPhotos]];
        
        if ([group numberOfAssets] > 0) {
            if ([group numberOfAssets] > numberOfAssets && numberOfAssets != 0) {
                // fetch recent one
                [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *istop) {
                    
                    if (result != nil) {
                        NSLog(@"Screenshot captured, uploading");

                        ALAssetRepresentation *rep = [result defaultRepresentation];
                        if (([rep dimensions].width == [UIScreen mainScreen].bounds.size.width * [[UIScreen mainScreen] scale] && [rep dimensions].height == [UIScreen mainScreen].bounds.size.height * [[UIScreen mainScreen] scale]) || ([rep dimensions].height == [UIScreen mainScreen].bounds.size.width * [[UIScreen mainScreen] scale] && [rep dimensions].width == [UIScreen mainScreen].bounds.size.height * [[UIScreen mainScreen] scale])) {

                            [[UIPasteboard generalPasteboard] setImage:[UIImage imageWithCGImage:[rep fullResolutionImage]]];
                        }
                        
                        *istop = YES;
                    }
                }];
            }
            
            numberOfAssets = [group numberOfAssets];
            
            // Pause
            *ostop = YES;
        }
    } failureBlock:^(NSError *error) {
        NSLog(@"%@", error);
    }];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:@"Yes"]) {
        [self saveImage:[(CLIPAlertView *)alertView image]];
    }
}

@end
