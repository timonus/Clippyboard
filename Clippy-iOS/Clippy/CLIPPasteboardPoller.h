//
//  CLIPPasteboardPoller.h
//  Clippy
//
//  Created by Tim Johnsen on 7/31/14.
//  Copyright (c) 2014 tijo. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CLIPPasteboardPollerDelegate;

@interface CLIPPasteboardPoller : NSObject

@property (nonatomic, weak) id<CLIPPasteboardPollerDelegate> delegate;

@property (nonatomic, assign) BOOL suppressChangeEvents;

@end

@protocol CLIPPasteboardPollerDelegate <NSObject>

- (void)pasteboardDidChange;

@end