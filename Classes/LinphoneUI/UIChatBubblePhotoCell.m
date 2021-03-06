/* UIChatRoomCell.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Library General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "UIChatBubblePhotoCell.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVKit/AVKit.h>

@implementation UIChatBubblePhotoCell {
	FileTransferDelegate *_ftd;
    CGSize imageSize, bubbleSize, videoDefaultSize;
    int actualAvailableWidth;
    ChatConversationTableView *chatTableView;
    //CGImageRef displayedImage;
}

#pragma mark - Lifecycle Functions

- (id)initWithIdentifier:(NSString *)identifier {
	if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier]) != nil) {
		// TODO: remove text cell subview
		NSArray *arrayOfViews =
			[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(self.class) owner:self options:nil];
		// resize cell to match .nib size. It is needed when resized the cell to
		// correctly adapt its height too
		UIView *sub = nil;
		for (int i = 0; i < arrayOfViews.count; i++) {
			if ([arrayOfViews[i] isKindOfClass:UIView.class]) {
				sub = arrayOfViews[i];
				break;
			}
		}
		[self setFrame:CGRectMake(0, 0, 5, 100)];
		[self addSubview:sub];
        chatTableView = VIEW(ChatConversationView).tableController;
        actualAvailableWidth = chatTableView.tableView.frame.size.width;
        videoDefaultSize = CGSizeMake(320, 240);
	}
	return self;
}

#pragma mark -
- (void)setEvent:(LinphoneEventLog *)event {
	if (!event || !(linphone_event_log_get_type(event) == LinphoneEventLogTypeConferenceChatMessage))
		return;

	super.event = event;
	[self setChatMessage:linphone_event_log_get_chat_message(event)];
}

- (void)setChatMessage:(LinphoneChatMessage *)amessage {
	_imageGestureRecognizer.enabled = NO;
    _openRecognizer.enabled = NO;
	_messageImageView.image = nil;
    _finalImage.image = nil;
    _finalImage.hidden = TRUE;
	_fileTransferProgress.progress = 0;
	[self disconnectFromFileDelegate];

	if (amessage) {
		const LinphoneContent *c = linphone_chat_message_get_file_transfer_information(amessage);
		if (c) {
			const char *name = linphone_content_get_name(c);
			for (FileTransferDelegate *aftd in [LinphoneManager.instance fileTransferDelegates]) {
				if (linphone_chat_message_get_file_transfer_information(aftd.message) &&
					(linphone_chat_message_is_outgoing(aftd.message) == linphone_chat_message_is_outgoing(amessage)) &&
					strcmp(name, linphone_content_get_name(
									 linphone_chat_message_get_file_transfer_information(aftd.message))) == 0) {
					LOGI(@"Chat message [%p] with file transfer delegate [%p], connecting to it!", amessage, aftd);
					[self connectToFileDelegate:aftd];
					break;
				}
			}
		}
	}

	[super setChatMessage:amessage];
}

- (void) loadImageAsset:(ALAsset*) asset thumb:(UIImage *)thumb  image:(UIImage *)image {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_finalImage setImage:image];
        [_messageImageView setImage:thumb];
        [_messageImageView setFullImageUrl:asset];
        [_messageImageView stopLoading];
        _messageImageView.hidden = YES;
        _imageGestureRecognizer.enabled = YES;
        _finalImage.hidden = NO;
    });
}

- (void) loadAsset:(ALAsset*) asset {
    UIImage *thumb = [[UIImage alloc] initWithCGImage:[asset thumbnail]];
    ALAssetRepresentation *representation = [asset defaultRepresentation];
    imageSize = [UIChatBubbleTextCell getMediaMessageSizefromOriginalSize:[representation dimensions] withWidth:chatTableView.tableView.frame.size.width];
    CGImageRef tmpImg = [self cropImageFromRepresentation:representation];
    UIImage *image = [[UIImage alloc] initWithCGImage:tmpImg];
	[self loadImageAsset:asset thumb:thumb image:image];
}

- (void) loadVideoAsset: (AVAsset *) asset {
    // Calculate a time for the snapshot - I'm using the half way mark.
    CMTime duration = [asset duration];
    CMTime snapshot = CMTimeMake(duration.value / 2, duration.timescale);
    // Create a generator and copy image at the time.
    // I'm not capturing the actual time or an error.
    AVAssetImageGenerator *generator =
    [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    CGImageRef imageRef = [generator copyCGImageAtTime:snapshot
                                            actualTime:nil
                                                 error:nil];
    
    UIImage *thumb = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    
    UIGraphicsBeginImageContext(videoDefaultSize);
    [thumb drawInRect:CGRectMake(0, 0, videoDefaultSize.width, videoDefaultSize.height)];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [self loadImageAsset:nil thumb:thumb image:image];
    
    // put the play button in the top
    CGRect newFrame = _playButton.frame;
    newFrame.origin.x = _finalImage.frame.origin.x/2;
    newFrame.origin.y = _finalImage.frame.origin.y/2;
    _playButton.frame = newFrame;
}

- (void) loadFileAsset {
    dispatch_async(dispatch_get_main_queue(), ^{
        _fileName.hidden = NO;
        _imageGestureRecognizer.enabled = NO;
        _openRecognizer.enabled = YES;
    });
}

- (void)update {
	if (self.message == nil) {
		LOGW(@"Cannot update message room cell: NULL message");
		return;
	}
	[super update];

	const char *url = linphone_chat_message_get_external_body_url(self.message);
	BOOL is_external =
		(url && (strstr(url, "http") == url)) || linphone_chat_message_get_file_transfer_information(self.message);
	NSString *localImage = [LinphoneManager getMessageAppDataForKey:@"localimage" inMessage:self.message];
    NSString *localVideo = [LinphoneManager getMessageAppDataForKey:@"localvideo" inMessage:self.message];
    NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
	BOOL fullScreenImage = NO;
	assert(is_external || localImage || localVideo || localFile);
    
    if (!(localImage || localVideo || localFile)) {
        _playButton.hidden = YES;
        _fileName.hidden = YES;
        _messageImageView.hidden = _cancelButton.hidden = (_ftd.message == nil);
        _downloadButton.hidden = !_cancelButton.hidden;
        _fileTransferProgress.hidden = NO;
    } else {
        // file is being saved on device - just wait for it
        if ([localImage isEqualToString:@"saving..."] || [localVideo isEqualToString:@"saving..."] || [localFile isEqualToString:@"saving..."]) {
            _cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden = _playButton.hidden = _fileName.hidden  = YES;
            fullScreenImage = YES;
        } else {
            if (localImage) {
                // we did not load the image yet, so start doing so
                if (_messageImageView.image == nil) {
                    NSURL *imageUrl = [NSURL URLWithString:localImage];
                    [_messageImageView startLoading];
                    __block LinphoneChatMessage *achat = self.message;
                    [LinphoneManager.instance.photoLibrary assetForURL:imageUrl resultBlock:^(ALAsset *asset) {                                                            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, (unsigned long)NULL),                                                                                                                                                                ^(void) {
                                                                                                                                                                                              if (achat != self.message) // Avoid glitch and scrolling
                                                                                                                                                                                                  return;
                                                                                                                                                                                              
                                                                                                                                                                                              if (asset) {
                                                                                                                                                                                                  [self loadAsset:asset];
                                                                                                                                                                                              }
                                                                                                                                                                                              else {
                                                                                                                                                                                                  [LinphoneManager.instance.photoLibrary
                                                                                                                                                                                                   enumerateGroupsWithTypes:ALAssetsGroupAll
                                                                                                                                                                                                   usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                                                                                                                                                                                                       [group enumerateAssetsWithOptions:NSEnumerationReverse
                                                                                                                                                                                                                              usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
                                                                                                                                                                                                                                  if([result.defaultRepresentation.url isEqual:imageUrl]) {
                                                                                                                                                                                                                                      [self loadAsset:result];
                                                                                                                                                                                                                                      *stop = YES;
                                                                                                                                                                                                                                  }
                                                                                                                                                                                                                              }];
                                                                                                                                                                                                   }
                                                                                                                                                                                                   failureBlock:^(NSError *error) {
                                                                                                                                                                                                       LOGE(@"Error: Cannot load asset from photo stream - %@", [error localizedDescription]);
                                                                                                                                                                                                   }];
                                                                                                                                                                                              }
                                                                                                                                                                                          });
                    } failureBlock:^(NSError *error) {
                        LOGE(@"Can't read image");
                    }];
                }
            } else if (localVideo) {
                if (_messageImageView.image == nil) {
                    [_messageImageView startLoading];
                    // read video from Documents
                    NSString *filePath = [LinphoneManager documentFile:localVideo];
                    NSURL *url = [NSURL fileURLWithPath:filePath];
                    AVAsset *asset = [AVAsset assetWithURL:url];
                    if (asset)
                        [self loadVideoAsset:asset];
                }
            } else if (localFile) {
                NSString *text = [NSString stringWithFormat:@"📎  %@",localFile];
                _fileName.text = text;
                [self loadFileAsset];
            }

            // we are uploading the image
            if (_ftd.message != nil) {
                _cancelButton.hidden = NO;
                _fileTransferProgress.hidden = NO;
                _downloadButton.hidden = YES;
                _playButton.hidden = YES;
                _fileName.hidden = YES;
            } else {
                _cancelButton.hidden = _fileTransferProgress.hidden = _downloadButton.hidden =  YES;
                fullScreenImage = YES;
                _playButton.hidden = localVideo ? NO : YES;
                _fileName.hidden = localFile ? NO : YES;
            }
        }
    }
	// resize image so that it take the full bubble space available
	CGRect newFrame = _totalView.frame;
	newFrame.origin.x = newFrame.origin.y = 0;
	if (!fullScreenImage) {
		newFrame.size.height -= _imageSubView.frame.size.height;
    }
	_messageImageView.frame = newFrame;
}

- (void)fileErrorBlock {
    DTActionSheet *sheet = [[DTActionSheet alloc] initWithTitle:NSLocalizedString(@"Can't open this file", nil)];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [sheet addCancelButtonWithTitle:NSLocalizedString(@"OK", nil) block:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [sheet showInView:PhoneMainView.instance.view];
        });
    });
}

- (IBAction)onDownloadClick:(id)event {
	[_ftd cancel];
	_ftd = [[FileTransferDelegate alloc] init];
	[self connectToFileDelegate:_ftd];
	[_ftd download:self.message];
	_cancelButton.hidden = NO;
	_downloadButton.hidden = YES;
    _playButton.hidden = YES;
    _fileName.hidden = YES;
}

- (IBAction)onPlayClick:(id)sender {
    NSString *localVideo = [LinphoneManager getMessageAppDataForKey:@"localvideo" inMessage:self.message];
    NSString *filePath = [LinphoneManager documentFile:localVideo];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([fileManager fileExistsAtPath:filePath]) {
        // create a player view controller
        AVPlayer *player = [AVPlayer playerWithURL:[[NSURL alloc] initFileURLWithPath:filePath]];
        AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
        [PhoneMainView.instance presentViewController:controller animated:YES completion:nil];
        controller.player = player;
        [player play];
    } else {
        [self fileErrorBlock];
    }
}

- (IBAction)onOpenClick:(id)event {
    NSString *localFile = [LinphoneManager getMessageAppDataForKey:@"localfile" inMessage:self.message];
    NSString *filePath = [LinphoneManager documentFile:localFile];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:filePath]) {
        ChatConversationView *view = VIEW(ChatConversationView);
        [view openResults:filePath];
    } else {
        [self fileErrorBlock];
    }
}


- (IBAction)onCancelClick:(id)sender {
	FileTransferDelegate *tmp = _ftd;
	[self disconnectFromFileDelegate];
	_fileTransferProgress.progress = 0;
	[tmp cancel];
}

- (void)onResendClick:(id)event {
	if (_downloadButton.hidden == NO) {
		// if download button is displayed, click on it
		[self onDownloadClick:event];
	} else if (_cancelButton.hidden == NO) {
		[self onCancelClick:event];
    } else {
		[super onResend];
	}
}

- (IBAction)onImageClick:(id)event {
	LinphoneChatMessageState state = linphone_chat_message_get_state(self.message);
	if (state == LinphoneChatMessageStateNotDelivered) {
		[self onResendClick:event];
	} else {
		if (![_messageImageView isLoading]) {
			ImageView *view = VIEW(ImageView);
			[PhoneMainView.instance changeCurrentView:view.compositeViewDescription];
			CGImageRef fullScreenRef = [[_messageImageView.fullImageUrl defaultRepresentation] fullScreenImage];
			UIImage *fullScreen = [UIImage imageWithCGImage:fullScreenRef];
			[view setImage:fullScreen];
		}
	}
}

#pragma mark - LinphoneFileTransfer Notifications Handling

- (void)connectToFileDelegate:(FileTransferDelegate *)aftd {
	if (aftd.message && linphone_chat_message_get_state(aftd.message) == LinphoneChatMessageStateFileTransferError) {
		LOGW(@"This file transfer failed unexpectedly, cleaning it");
		[aftd stopAndDestroy];
		return;
	}

	_ftd = aftd;
	_fileTransferProgress.progress = 0;
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(onFileTransferSendUpdate:)
											   name:kLinphoneFileTransferSendUpdate
											 object:_ftd];
	[NSNotificationCenter.defaultCenter addObserver:self
										   selector:@selector(onFileTransferRecvUpdate:)
											   name:kLinphoneFileTransferRecvUpdate
											 object:_ftd];
}

- (void)disconnectFromFileDelegate {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	_ftd = nil;
}

- (void)onFileTransferSendUpdate:(NSNotification *)notif {
	LinphoneChatMessageState state = [[[notif userInfo] objectForKey:@"state"] intValue];

	if (state == LinphoneChatMessageStateInProgress) {
		float progress = [[[notif userInfo] objectForKey:@"progress"] floatValue];
		// When uploading a file, the self.message file is first uploaded to the server,
		// so we are in progress state. Then state goes to filetransfertdone. Then,
		// the exact same self.message is sent to the other participant and we come
		// back to in progress again. This second time is NOT an upload, so we must
		// not update progress!
		_fileTransferProgress.progress = MAX(_fileTransferProgress.progress, progress);
		_fileTransferProgress.hidden = _cancelButton.hidden = (_fileTransferProgress.progress == 1.f);
	} else {
		ChatConversationView *view = VIEW(ChatConversationView);
		[view.tableController updateEventEntry:self.event];
	}
}
- (void)onFileTransferRecvUpdate:(NSNotification *)notif {
	LinphoneChatMessageState state = [[[notif userInfo] objectForKey:@"state"] intValue];
	if (state == LinphoneChatMessageStateInProgress) {
		float progress = [[[notif userInfo] objectForKey:@"progress"] floatValue];
		_fileTransferProgress.progress = MAX(_fileTransferProgress.progress, progress);
		_fileTransferProgress.hidden = _cancelButton.hidden = (_fileTransferProgress.progress == 1.f);
	} else {
		ChatConversationView *view = VIEW(ChatConversationView);
		[view.tableController updateEventEntry:self.event];
	}
}

+ (CGImageRef)resizeCGImage:(CGImageRef)image toWidth:(int)width andHeight:(int)height {
    // create context, keeping original image properties
    CGColorSpaceRef colorspace = CGImageGetColorSpace(image);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height,
                                                 CGImageGetBitsPerComponent(image),
                                                 CGImageGetBytesPerRow(image),
                                                 colorspace,
                                                 CGImageGetAlphaInfo(image));
    CGColorSpaceRelease(colorspace);
    
    if(context == NULL)
        return nil;
    
    // draw image to context (resizing it)
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    // extract resulting image from context
    CGImageRef imgRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    
    return imgRef;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    //if (!isAssetLoaded) return;
    UITableView *tableView = VIEW(ChatConversationView).tableController.tableView;
    BOOL is_outgoing = linphone_chat_message_is_outgoing(super.message);
    CGRect bubbleFrame = super.bubbleView.frame;
    int origin_x;
    
    bubbleSize = [UIChatBubbleTextCell ViewSizeForMessage:[self message] withWidth:chatTableView.tableView.frame.size.width];
    
    bubbleFrame.size = bubbleSize;
    
    if (tableView.isEditing) {
        origin_x = 0;
    } else {
        origin_x = (is_outgoing ? self.frame.size.width - bubbleFrame.size.width : 0);
    }
    
    bubbleFrame.origin.x = origin_x;
    
    super.bubbleView.frame = bubbleFrame;
}

- (CGImageRef)cropImageFromRepresentation:(ALAssetRepresentation*)rep {
    CGImageRef newImage = [rep fullResolutionImage];
    CGSize originalSize = [rep dimensions];
    float originalAspectRatio = originalSize.width / originalSize.height;
    // We resize in width and crop in height
    if (originalSize.width > imageSize.width) {
        int height = imageSize.width / originalAspectRatio;
        newImage = [self.class resizeCGImage:newImage toWidth:imageSize.width andHeight:height];
        originalSize.height = height;
    }
    CGRect cropRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
    if (imageSize.height < originalSize.height) cropRect.origin.y = (originalSize.height - imageSize.height)/2;
    newImage = CGImageCreateWithImageInRect(newImage, cropRect);
    LOGD([NSString stringWithFormat:@"Image size : width = %g, height = %g", imageSize.width, imageSize.height]);
    LOGD([NSString stringWithFormat:@"Bubble size : width = %g, height = %g", super.bubbleView.frame.size.width, super.bubbleView.frame.size.height]);
    return newImage;
}


@end


