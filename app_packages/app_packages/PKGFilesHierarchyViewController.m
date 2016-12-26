/*
 Copyright (c) 2016, Stephane Sudre
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 - Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 - Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 - Neither the name of the WhiteBox nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "PKGFilesHierarchyViewController.h"

#import "PKGPayloadTreeNode+UI.h"
#import "PKGFileItem+UI.h"

#import "NSOutlineView+Selection.h"
#import "NSAlert+block.h"

#import "PKGApplicationPreferences.h"

#import "PKGTablePayloadFilenameCellView.h"

#import "PKGOwnershipAndReferenceStyleViewController.h"
#import "PKGPayloadDropView.h"

#import "PKGPackagePayloadDataSource.h"

#import "PKGFileNameFormatter.h"

@interface PKGFilesHierarchyOpenPanelDelegate : NSObject<NSOpenSavePanelDelegate>

	@property NSArray * sibblings;
	@property id<PKGFilePathConverter> filePathConverter;

@end

@implementation PKGFilesHierarchyOpenPanelDelegate

- (BOOL)panel:(NSOpenPanel *)inPanel shouldEnableURL:(NSURL *)inURL
{
	if (inURL.isFileURL==NO)
		return NO;
	
	NSString * tLastPathComponent=[inURL.path lastPathComponent];
	
	if ([self.sibblings indexOfObjectPassingTest:^BOOL(PKGPayloadTreeNode *bPayloadTreeNode,NSUInteger bIndex,BOOL * bOutStop){
	
		return ([tLastPathComponent caseInsensitiveCompare:bPayloadTreeNode.fileName]==NSOrderedSame);
	
	}]!=NSNotFound)
		return NO;
	
	
	return YES;
}

@end


NSString * const PKGFilesHierarchyDidRenameFolderNotification=@"PKGFilesHierarchyDidRenameFolderNotification";


@interface PKGFilesHierarchyViewController () <NSOutlineViewDelegate,NSControlTextEditingDelegate>
{
	IBOutlet NSTextField * _viewLabel;
	
	IBOutlet NSButton * _addButton;
	IBOutlet NSButton * _removeButton;
	
	IBOutlet NSTextField * _viewInformationLabel;
	
	PKGOwnershipAndReferenceStyleViewController * _ownershipAndReferenceStyleViewController;
	PKGFilesHierarchyOpenPanelDelegate * _openPanelDelegate;
	
	PKGFileNameFormatter * _cachedFileNameFormatter;
	
	BOOL _highlightExcludedItems;
	NSArray * _optimizedFilesFilters;
	
	NSTimeInterval _lastRefreshTimeMark;
}

- (IBAction)showInFinder:(id)sender;

- (IBAction)addFiles:(id)sender;
- (IBAction)addNewFolder:(id)sender;

- (IBAction)renameFolder:(id)sender;

- (IBAction)delete:(id)sender;


- (IBAction)expand:(id)sender;
- (IBAction)contract:(id)sender;

// Notifications

- (void)highlightExludedFilesStateDidChange:(NSNotification *)inNotification;

- (void)windowDidBecomeMain:(NSNotification *)inNotification;

@end

@implementation PKGFilesHierarchyViewController

- (instancetype)initWithNibName:(NSString *)inNibName bundle:(NSBundle *)inBundle
{
	self=[super initWithNibName:inNibName bundle:inBundle];
	
	if (self!=nil)
	{
		_managedFileAttributes=PKGFileOwnerAndGroupAccounts|PKGFilePosixPermissions;
		
		_label=@"";
		_informationLabel=@"";
		
		_cachedFileNameFormatter=[PKGFileNameFormatter new];
		_cachedFileNameFormatter.fileNameCanStartWithDot=YES;
	}
	
	return self;
}

#pragma mark -

- (NSString *)nibName
{
	return @"PKGFilesHierarchyViewController";
}

- (id<PKGFilePathConverter>)filePathConverter
{
	return (id<PKGFilePathConverter>) [NSApplication sharedApplication].delegate;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	 /*ICFilePboardType,
	 ICFileExternalPboardType*/
	
	// Owner and Group
	
	BOOL tHideColumn=(_managedFileAttributes & PKGFileOwnerAndGroupAccounts)==0;
	
	[self.outlineView tableColumnWithIdentifier:@"file.owner"].hidden=tHideColumn;
	[self.outlineView tableColumnWithIdentifier:@"file.group"].hidden=tHideColumn;
	
	// Permissions
	
	tHideColumn=(_managedFileAttributes & PKGFilePosixPermissions)==0;
	
	[self.outlineView tableColumnWithIdentifier:@"file.permissions"].hidden=tHideColumn;
	
	
	[self.outlineView registerForDraggedTypes:[PKGPayloadDataSource supportedDraggedTypes]];
	
    // Do view setup here.
}

#pragma mark -

- (BOOL)highlightExcludedItems
{
	return [PKGApplicationPreferences sharedPreferences].highlightExcludedFiles;
}

- (void)setManagedFileAttributes:(PKGManagedAttributesOptions)inOptions
{
	if (inOptions!=_managedFileAttributes)
	{
		_managedFileAttributes=inOptions;
	
		if (self.outlineView!=nil)
		{
			// Owner and Group
			
			BOOL tHideColumn=(_managedFileAttributes & PKGFileOwnerAndGroupAccounts)==0;
			
			[self.outlineView tableColumnWithIdentifier:@"file.owner"].hidden=tHideColumn;
			[self.outlineView tableColumnWithIdentifier:@"file.group"].hidden=tHideColumn;
			
			// Permissions
			
			tHideColumn=(_managedFileAttributes & PKGFilePosixPermissions)==0;
			
			[self.outlineView tableColumnWithIdentifier:@"file.permissions"].hidden=tHideColumn;
		}
	}
}

#pragma mark -

- (void)WB_viewWillAdd
{
	_viewLabel.stringValue=_label;
	_viewInformationLabel.stringValue=_informationLabel;
	
	self.outlineView.dataSource=_hierarchyDatasource;
	
	if ([self.view isKindOfClass:[PKGPayloadDropView class]]==YES)
		((PKGPayloadDropView *)self.view).delegate=(id<PKGFileDeadDropViewDelegate>)_hierarchyDatasource;
	
	
	_highlightExcludedItems=[self highlightExcludedItems];
	_optimizedFilesFilters=[self project].settings.optimizedFilesFilters;
	
	
	_lastRefreshTimeMark=[NSDate timeIntervalSinceReferenceDate];
	// A COMPLETER
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(highlightExludedFilesStateDidChange:) name:PKGPreferencesFilesHighlightExcludedFilesDidChangeNotification object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowDidBecomeMain:) name:NSWindowDidBecomeMainNotification object:self.view.window];
}

- (void)WB_viewDidAdd
{
	// A COMPLETER
	
	_addButton.enabled=(_hierarchyDatasource.editableRootNodes==YES);
	_removeButton.enabled=NO;
}

- (void)WB_viewWillRemove
{
	// A COMPLETER
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:PKGPreferencesFilesHighlightExcludedFilesDidChangeNotification object:nil];
}

- (void)refreshHierarchy
{
	[self.outlineView reloadData];
}

#pragma mark -

- (void)setHierarchyDatasource:(id<NSOutlineViewDataSource>)inDataSource
{
	_hierarchyDatasource=inDataSource;
	
	if (self.outlineView!=nil)
		self.outlineView.dataSource=_hierarchyDatasource;
}

- (void)setLabel:(NSString *)inLabel
{
	_label=(inLabel!=nil) ? [inLabel copy] : @"";
	
	if (_viewLabel!=nil)
		_viewLabel.stringValue=_label;
}

- (void)setInformationLabel:(NSString *)inInformationLabel
{
	_informationLabel=(inInformationLabel!=nil) ? [inInformationLabel copy] : @"";
	
	if (_viewInformationLabel!=nil)
		_viewInformationLabel.stringValue=_informationLabel;
}

#pragma mark -

- (BOOL)outlineView:(NSOutlineView *)inOutlineView shouldDeleteItems:(NSArray *)inItems
{
	if (inOutlineView==nil || inItems==nil)
		return NO;
	
	NSArray * tMinimumCover=[PKGTreeNode minimumNodeCoverFromNodesInArray:inItems];
	
	if (tMinimumCover.count==0)
		return NO;
	
	for(PKGPayloadTreeNode * tTreeNode in tMinimumCover)
	{
		if ([tTreeNode isTemplateNode]==YES)
			return NO;
	}
	
	return YES;
}

#pragma mark -

- (NSView *)outlineView:(NSOutlineView *)inOutlineView viewForTableColumn:(NSTableColumn *)inTableColumn item:(PKGPayloadTreeNode *)inPayloadTreeNode
{
	if (inOutlineView!=self.outlineView)
		return nil;
	
	NSString * tTableColumnIdentifier=[inTableColumn identifier];
	NSTableCellView * tView=[inOutlineView makeViewWithIdentifier:tTableColumnIdentifier owner:self];
	
	if ([inPayloadTreeNode needsRefresh:_lastRefreshTimeMark]==YES)
		[inPayloadTreeNode refreshWithAbsolutePath:[inPayloadTreeNode referencedPathUsingConverter:self.filePathConverter]
									   fileFilters:(_highlightExcludedItems==YES) ? _optimizedFilesFilters : nil];
	
	if ([tTableColumnIdentifier isEqualToString:@"file.name"]==YES)
	{
		PKGTablePayloadFilenameCellView *tPayloadFileNameCellView=(PKGTablePayloadFilenameCellView *)tView;
		
		tPayloadFileNameCellView.attributedImageView.attributedImage=inPayloadTreeNode.nameAttributedIcon;
		tPayloadFileNameCellView.attributedImageView.drawsTarget=[self.hierarchyDatasource outlineView:inOutlineView shouldDrawBadgeInTableColum:inTableColumn forItem:inPayloadTreeNode];
		//[tView.imageView unregisterDraggedTypes];	// To prevent the imageView from interfering with drag and drop
		
		NSAttributedString * tAttributedString=inPayloadTreeNode.nameAttributedTitle;
		
		tView.textField.attributedStringValue=tAttributedString;
		tView.textField.textColor=[tAttributedString attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];	// Because the text color is overriding the attributes.
		tView.textField.editable=inPayloadTreeNode.isNameTitleEditable;
		tView.textField.formatter=_cachedFileNameFormatter;
		
		return tView;
	}
	
	if ([tTableColumnIdentifier isEqualToString:@"file.owner"]==YES)
	{
		tView.textField.stringValue=inPayloadTreeNode.ownerTitle;
		
		return tView;
	}
	
	if ([tTableColumnIdentifier isEqualToString:@"file.group"]==YES)
	{
		tView.textField.stringValue=inPayloadTreeNode.groupTitle;
		
		return tView;
	}
	
	if ([tTableColumnIdentifier isEqualToString:@"file.permissions"]==YES)
	{
		tView.textField.stringValue=inPayloadTreeNode.posixPermissionsTitle;
		
		return tView;
	}
	
	return nil;
}

#pragma mark -

- (IBAction)showInFinder:(id)sender
{
	NSIndexSet * tSelectionIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;
	
	NSWorkspace * tSharedWorkspace=[NSWorkspace sharedWorkspace];
	
	[tSelectionIndexSet enumerateIndexesUsingBlock:^(NSUInteger bIndex,BOOL * bOutStop){
		
		PKGPayloadTreeNode * tPayloadTreeNode=[self.outlineView itemAtRow:bIndex];
		
		[tSharedWorkspace selectFile:[tPayloadTreeNode referencedPathUsingConverter:self.filePathConverter] inFileViewerRootedAtPath:@""];
	}];
}

- (IBAction)addFiles:(id)sender
{
	NSOpenPanel * tOpenPanel=[NSOpenPanel openPanel];
	
	tOpenPanel.resolvesAliases=NO;
	tOpenPanel.canChooseFiles=YES;
	tOpenPanel.canChooseDirectories=YES;
	tOpenPanel.allowsMultipleSelection=YES;
	tOpenPanel.treatsFilePackagesAsDirectories=YES;
	tOpenPanel.showsHiddenFiles=[PKGApplicationPreferences sharedPreferences].showAllFilesInOpenDialog;
	
	NSIndexSet * tSelectionIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;
	
	PKGTreeNode * tParentNode=nil;
	
	if (tSelectionIndexSet.count>0)
	{
		NSInteger tClickedRow=self.outlineView.clickedRow;
		
		if (tClickedRow==-1)
			tClickedRow=tSelectionIndexSet.firstIndex;
		
		PKGPayloadTreeNode * tNode=[self.outlineView itemAtRow:tClickedRow];
		
		tParentNode=(tNode.isLeaf==NO) ? tNode : tNode.parent;
	}
	
	_openPanelDelegate=[PKGFilesHierarchyOpenPanelDelegate new];
	
	_openPanelDelegate.filePathConverter=self.filePathConverter;
	_openPanelDelegate.sibblings=(tParentNode==nil) ? self.hierarchyDatasource.rootNodes : tParentNode.children;
	
	tOpenPanel.delegate=_openPanelDelegate;
	
	tOpenPanel.prompt=NSLocalizedString(@"Add...",@"No comment");
	
	__block BOOL tKeepOwnerAndGroup=(self.managedFileAttributes==0) ? NO : [PKGApplicationPreferences sharedPreferences].keepOwnershipKey;
	__block PKGFilePathType tReferenceStyle=[PKGApplicationPreferences sharedPreferences].defaultFilePathReferenceStyle;
	
	if ([PKGApplicationPreferences sharedPreferences].showOwnershipAndReferenceStyleCustomizationDialog==YES)
	{
		_ownershipAndReferenceStyleViewController=[PKGOwnershipAndReferenceStyleViewController new];
		
		_ownershipAndReferenceStyleViewController.canChooseOwnerAndGroupOptions=((_managedFileAttributes & PKGFileOwnerAndGroupAccounts)!=0);
		_ownershipAndReferenceStyleViewController.keepOwnerAndGroup=tKeepOwnerAndGroup;
		
		_ownershipAndReferenceStyleViewController.referenceStyle=tReferenceStyle;
		
		NSView * tAccessoryView=_ownershipAndReferenceStyleViewController.view;
		
		[_ownershipAndReferenceStyleViewController WB_viewWillAdd];
		
		[tOpenPanel setAccessoryView:tAccessoryView];
		
		[_ownershipAndReferenceStyleViewController WB_viewDidAdd];
	}
	
	[tOpenPanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger bResult){
	
		if (bResult==NSFileHandlingPanelOKButton)
		{
			if ([PKGApplicationPreferences sharedPreferences].showOwnershipAndReferenceStyleCustomizationDialog==YES)
			{
				tKeepOwnerAndGroup=_ownershipAndReferenceStyleViewController.keepOwnerAndGroup;
				tReferenceStyle=_ownershipAndReferenceStyleViewController.referenceStyle;
			}
			
			NSArray * tPaths=[tOpenPanel.URLs WB_arrayByMappingObjectsUsingBlock:^(NSURL * bURL,NSUInteger bIndex){
				
				return bURL.path;
			}];
			
			if ([self.hierarchyDatasource outlineView:self.outlineView
							 addFileSystemItemsAtPaths:tPaths
										referenceType:tReferenceStyle
											toParents:(tParentNode==nil) ? nil : @[tParentNode]
											  options:(tKeepOwnerAndGroup==YES) ? PKGPayloadAddKeepOwnership : 0]==YES)
			{
				[self noteDocumentHasChanged];
			}
		}
		
		_ownershipAndReferenceStyleViewController=nil;
	}];
}

- (IBAction)addNewFolder:(id)sender
{
	NSIndexSet * tSelectionIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;
	NSInteger tClickedRow=self.outlineView.clickedRow;
	
	// Selection is not empty and no row was clicked
	
	if (tSelectionIndexSet.count>0 && tClickedRow==-1)
		tClickedRow=tSelectionIndexSet.firstIndex;
	
	if ([self.hierarchyDatasource outlineView:self.outlineView addNewFolderToParent:(tClickedRow!=-1) ? ((PKGTreeNode *)[self.outlineView itemAtRow:tClickedRow]) : nil]==NO)
		return;
	
	// Enter edition mode
	
	NSInteger tRow=[self.outlineView selectedRow];
	
	if (tRow==-1)
		return;
	
	[self.outlineView scrollRowToVisible:tRow];
	
	[self.outlineView editColumn:[self.outlineView columnWithIdentifier:@"file.name"] row:tRow withEvent:nil select:YES];
}

- (IBAction)renameFolder:(id)sender
{
	NSInteger tEditedRow=[self.outlineView rowForView:sender];
	
	if (tEditedRow==-1)
		return;
	
	PKGPayloadTreeNode * tEditedNode=[self.outlineView itemAtRow:tEditedRow];
	
	NSString * tNewName=[sender stringValue];
	
	if ([tEditedNode.fileName compare:tNewName]==NSOrderedSame)
		return;
	
	if ([tEditedNode.fileName caseInsensitiveCompare:tNewName]!=NSOrderedSame)
	{
		if ([PKGPayloadTreeNode validateFolderName:tNewName]==NO ||
			[[self.hierarchyDatasource siblingsOfItem:tEditedNode] indexesOfObjectsPassingTest:^BOOL(PKGPayloadTreeNode * bTreeNode,NSUInteger bIndex,BOOL * bOutStop){
	
				return ([bTreeNode.fileName caseInsensitiveCompare:tNewName]==NSOrderedSame);
	
			}].count>0)
		{
			NSBeep();
		
			[self.outlineView editColumn:[self.outlineView columnWithIdentifier:@"file.name"] row:tEditedRow withEvent:nil select:YES];
		
			return;
		}
	}
	
	[tEditedNode setNewFolderName:tNewName];
	
	// Sort and update selection
	
	PKGTreeNode * tParent=tEditedNode.parent;
	
	[tEditedNode removeFromParent];
	
	[self.hierarchyDatasource outlineView:self.outlineView addItem:tEditedNode toParent:tParent];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:PKGFilesHierarchyDidRenameFolderNotification object:self.outlineView userInfo:@{@"NSObject":tEditedNode}];
}

- (IBAction)delete:(id)sender
{
	NSIndexSet * tIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;
	
	if (tIndexSet.count<1)
		return;
	
	NSAlert * tAlert=[[NSAlert alloc] init];
	tAlert.messageText=(tIndexSet.count==1) ? NSLocalizedString(@"Do you really want to remove this item?",@"No comment") : NSLocalizedString(@"Do you really want to remove these items?",@"No comment");
	tAlert.informativeText=NSLocalizedString(@"This cannot be undone.",@"No comment");
	
	[tAlert addButtonWithTitle:NSLocalizedString(@"Remove",@"No comment")];
	[tAlert addButtonWithTitle:NSLocalizedString(@"Cancel",@"No comment")];
	
	[tAlert WB_beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse bResponse){
	
		if (bResponse!=NSAlertFirstButtonReturn)
			return;
		
		[self.hierarchyDatasource outlineView:self.outlineView removeItems:[self.outlineView WB_itemsAtRowIndexes:tIndexSet]];
	}];
}

- (IBAction)expand:(id)sender
{
	// A COMPLETER
}

- (IBAction)contract:(id)sender
{
	NSIndexSet * tSelectionIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;
	
	NSUInteger tIndex=tSelectionIndexSet.firstIndex;
	
	PKGPayloadTreeNode * tExpandedNode=[self.outlineView itemAtRow:tIndex];
	
	[self.outlineView collapseItem:tExpandedNode];
	
	[tExpandedNode contract];
	
	[self noteDocumentHasChanged];
	
	[self.outlineView reloadItem:tExpandedNode];
}

- (BOOL)validateMenuItem:(NSMenuItem *)inMenuItem
{
	SEL tSelector=inMenuItem.action;
	
	NSIndexSet * tSelectionIndexSet=self.outlineView.WB_selectedOrClickedRowIndexes;

	NSInteger tSelectedCount=tSelectionIndexSet.count;
	
	if (tSelectedCount==0)
	{
		// New Folder
		
		if (tSelector==@selector(addNewFolder:))
			return _hierarchyDatasource.editableRootNodes;
		
		if (tSelector==@selector(addFiles:))
			return _hierarchyDatasource.editableRootNodes;
		
		return NO;
	}
	
	if (tSelectedCount>0)
	{
		// Add Files
		
		if (tSelector==@selector(addFiles:))
			return YES;
		
		// New Folder
		
		if (tSelector==@selector(addNewFolder:))
		{
			NSInteger tClickedRow=self.outlineView.clickedRow;
			
			if (tClickedRow==-1)
				tClickedRow=tSelectionIndexSet.firstIndex;
			
			PKGPayloadTreeNode * tParentNode=[self.outlineView itemAtRow:tClickedRow];
			
			if (tParentNode.isLeaf==NO)
				return YES;
			
			tParentNode=(PKGPayloadTreeNode *)tParentNode.parent;
			
			if (tParentNode!=NULL)
				return YES;
			
			return _hierarchyDatasource.editableRootNodes;
		}
		
		// Show in Finder
		
		if (tSelector==@selector(showInFinder:))
		{
			__block BOOL tIsValidated=YES;
			
			[tSelectionIndexSet enumerateIndexesUsingBlock:^(NSUInteger bIndex,BOOL * bOutStop){
			
				PKGPayloadTreeNode * tPayloadTreeNode=[self.outlineView itemAtRow:bIndex];
				
				if ([tPayloadTreeNode isFileSystemItemNode]==NO)
				{
					tIsValidated=NO;
					*bOutStop=NO;
				}
			}];
			
			return tIsValidated;
		}
		
		// Delete
		
		if (tSelector==@selector(delete:))
			return [self outlineView:self.outlineView shouldDeleteItems:[self.outlineView WB_selectedOrClickedItems]];
	}
	
	if (tSelectedCount==1)
	{
		PKGPayloadTreeNode * tPayloadTreeNode=[self.outlineView itemAtRow:tSelectionIndexSet.firstIndex];

		// Contraction and expansion actions
		
		if ([tPayloadTreeNode isFileSystemItemNode]==NO)
			return NO;
		
		if (tSelector==@selector(contract:))
			return ([tPayloadTreeNode isLeaf]==NO);
		
		if (tSelector==@selector(expand:))
		{
			if ([tPayloadTreeNode isLeaf]==NO)
				return NO;
			
			NSString * tReferencedPath=[tPayloadTreeNode referencedPathUsingConverter:self.filePathConverter];
			
			if (tReferencedPath==nil)
			{
				NSLog(@"Could not compute the referenced path for %@",tPayloadTreeNode);
				return NO;
			}
			
			NSError * tError=nil;
			NSDictionary * tAttributes=[[NSFileManager defaultManager] attributesOfItemAtPath:tReferencedPath error:&tError];
			
			if (tAttributes==nil)
			{
				if (tError!=nil && [tError.domain isEqualToString:NSCocoaErrorDomain]==YES)
				{
					// A COMPLETER
				}
				
				return NO;
			}
			
			return ([tAttributes[NSFileType] isEqualToString:NSFileTypeDirectory]==YES);
		}
	}
	
	return NO;
}

#pragma mark - PKGPayloadDataSourceDelegate

- (void)payloadDataDidChange:(PKGPayloadDataSource *)inPayloadDataSource
{
	[self noteDocumentHasChanged];
}

#pragma mark - NSControlTextEditingDelegate

- (void)control:(NSControl *)inControl didFailToValidatePartialString:(NSString *)string errorDescription:(NSString *)inError
{
	NSBeep();
}

#pragma mark - Notifications

- (void)outlineViewSelectionDidChange:(NSNotification *)inNotification
{
	if (inNotification.object!=self.outlineView)
		return;
	
	NSIndexSet * tSelectionIndexSet=self.outlineView.selectedRowIndexes;
	
	// Delete button state
	
	if (tSelectionIndexSet.count==0)
	{
		_addButton.enabled=_hierarchyDatasource.editableRootNodes;
		_removeButton.enabled=NO;
		
		return;
	}
	
	_addButton.enabled=YES;
	_removeButton.enabled=YES;
		
	[tSelectionIndexSet enumerateIndexesUsingBlock:^(NSUInteger bIndex,BOOL * bOutStop){
		
		PKGPayloadTreeNode * tPayloadTreeNode=[self.outlineView itemAtRow:bIndex];
		
		if ([tPayloadTreeNode isTemplateNode]==YES)
		{
			_removeButton.enabled=NO;
			*bOutStop=NO;
		}
	}];
	
	// A COMPLETER
}

- (void)highlightExludedFilesStateDidChange:(NSNotification *)inNotification
{
	_highlightExcludedItems=[self highlightExcludedItems];
	
	[self.outlineView reloadData];
}

- (void)windowDidBecomeMain:(NSNotification *)inNotification
{
	_lastRefreshTimeMark=[NSDate timeIntervalSinceReferenceDate];
	
	[self.outlineView reloadData];
}

@end
