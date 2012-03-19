//
//  StamperContoller.m
//  RelayUSBStamper
//
//  Created by Dusseau, Jim on 5/22/11.
//  Copyright 2011 Jim Dusseau. All rights reserved.
//

#import "StamperContoller.h"


@implementation StamperContoller

//The more you have going concurrently, the longer each one is going to take.
//It's tough to know what's right in this situation, as bandwidth is allocated
//by USB controllers on the motherboard
#define STAMPING_QUEUE_LENGTH 2

-(NSString *)payloadFolderPath
{
   //TODOJDD prompt the user for this
   return [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Payload"];
}

-(void)stampDevice:(NSString *)devicePath
{
   NSFileManager *manager = [[NSFileManager alloc] init];
   
   //Format drive
   NSArray *driveContents = [manager contentsOfDirectoryAtPath:devicePath error:NULL];
   for (NSString *item in driveContents)
   {
      [manager removeItemAtPath:[devicePath stringByAppendingPathComponent:item] error:NULL];
   }
   
   //Do Copy
   NSString *payloadDirPath = [self payloadFolderPath];
   NSArray *payloadDirContents = [manager contentsOfDirectoryAtPath:payloadDirPath error:NULL];
   if(!payloadDirContents)
   {
      NSLog(@"No files found in payload directory. Aborting stamping");
      return;
   }
   
   for(NSString *payloadItem in payloadDirContents)
   {
      NSError *error = nil;
      BOOL copySuccess = [manager copyItemAtPath:[payloadDirPath stringByAppendingPathComponent:payloadItem] toPath:[devicePath stringByAppendingPathComponent:payloadItem] error:&error];
      if(!copySuccess)
      {
         NSLog(@"Copy error: %@. Stamping partially completed", error);
         return;
      }
   }
   
   [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:devicePath];
}


-(void)promptForStamping:(NSString *)devicePath
{
   NSString *messageString = [NSString stringWithFormat:@"Do you want to copy the Payload onto %@?", [devicePath lastPathComponent]];
   NSString *infoString = @"Warning: This will format the drive";
   NSAlert *alert = [NSAlert alertWithMessageText:messageString defaultButton:@"Format and Stamp" alternateButton:@"Ignore Drive" otherButton:nil informativeTextWithFormat:infoString];
   
   NSInteger returnCode = [alert runModal];
   if(returnCode == NSAlertDefaultReturn)
   {
      [stampingQueue addOperationWithBlock:^{
         //TODOJDD do this without capturing self. Break up this class
         [self stampDevice:devicePath];
      }];
   }
}

-(void)driveMounted:(NSNotification *)n
{
   NSString* devicePath = [[n userInfo] objectForKey:@"NSDevicePath"];
   [self promptForStamping:devicePath];
}

-(void)setupDirectories
{
   NSFileManager *manager = [NSFileManager new];
   NSString *payloadFolderPath = [self payloadFolderPath];
   
   BOOL isDirectory = NO;
   BOOL directoryExists = [manager fileExistsAtPath:payloadFolderPath isDirectory:&isDirectory];
   if(!directoryExists)
   {
      BOOL createDirSucceeded = [manager createDirectoryAtPath:payloadFolderPath withIntermediateDirectories:NO attributes:nil error:NULL];
      BOOL fileInitSucceeded = [@"Put files in this folder that you'd like copied to the external drive" writeToFile:[payloadFolderPath stringByAppendingPathComponent:@"Readme.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
      NSAssert(createDirSucceeded && fileInitSucceeded, @"Init failed");
   }
}

- (id)init
{
   self = [super init];
   if (self)
   {
      [self setupDirectories];
      
      stampingQueue = [NSOperationQueue new];
      if(STAMPING_QUEUE_LENGTH > 0)
      {
         [stampingQueue setMaxConcurrentOperationCount:STAMPING_QUEUE_LENGTH];
      }
   }
   
   return self;
}

-(void)awakeFromNib
{
   NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
   [center addObserver:self selector:@selector(driveMounted:) name:NSWorkspaceDidMountNotification object:nil];
}

- (void)dealloc
{
   [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
   
   [stampingQueue setSuspended:YES];
   [stampingQueue waitUntilAllOperationsAreFinished]; //TODOJDD this isn't going to do what I thought because the queue captures self. Fix this
}



@end
