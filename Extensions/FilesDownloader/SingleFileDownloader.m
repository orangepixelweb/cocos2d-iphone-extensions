//
//  SingleFileDownloader.m
//  iTraceur - Parkour / Freerunning Platform Game
//  
//
//  Created by Stepan Generalov on 6/18/10.
//  Copyright 2010-2011 Parkour Games. All rights reserved.
//

#import "SingleFileDownloader.h"

#ifndef MYLOG
	#ifdef DEBUG
		#define MYLOG(...) NSLog(__VA_ARGS__)
	#else
		#define MYLOG(...) do {} while (0)
	#endif
#endif

@interface SingleFileDownloader (Private)

+ (NSString *) destinationDirectoryPath;
+ (NSString *) tmpSuffix;
+ (NSFileHandle *) newFileWithName: (NSString *) newFilename; 

@end

@interface SingleFileDownloader (NSURLConnectionDelegate) 

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;

@end

@implementation SingleFileDownloader

+ (NSString *) tmpSuffix
{
    return @".tmp";
}

+ (NSString *) tmpPathWithFilename: (NSString *) aFilename
{
    return [NSString stringWithFormat:@"%@/%@%@", [SingleFileDownloader destinationDirectoryPath], aFilename, [self tmpSuffix]];
}

+ (NSString *) destinationDirectoryPath
{
    NSString *cachesDirectoryPath =
        [ NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
    
    return cachesDirectoryPath;
}

+ (NSFileHandle *) newFileWithName: (NSString *) newFilename
{    
    //creating caches directory if needed
    NSString *cachesDirectoryPath = [SingleFileDownloader destinationDirectoryPath];
    
    BOOL isDirectory = NO;
    BOOL exists = [ [NSFileManager defaultManager] fileExistsAtPath:cachesDirectoryPath isDirectory:&isDirectory];
    
    if ( exists && isDirectory )
    {
        MYLOG(@"SingleFileDownloader#newFileWithName: %@ exists",cachesDirectoryPath);
    }
    else
    {
        MYLOG(@"SingleFileDownloader#newFileWithName: %@ not exists! Creating...",cachesDirectoryPath );
        if ( [ [NSFileManager defaultManager] createDirectoryAtPath:cachesDirectoryPath withIntermediateDirectories: YES attributes: nil error: NULL] ) 
        {
            MYLOG(@"SingleFileDownloader#newFileWithName: SUCCESSFULL creating caches directory!");
        }
        else
        {
            MYLOG(@"SingleFileDownloader#newFileWithName: creating caches directory FAILED!");
            return nil;
        }
    }
    
    NSString * myFilePath = [SingleFileDownloader tmpPathWithFilename: newFilename];
    
    if ( [ [NSFileManager defaultManager] createFileAtPath:myFilePath contents:nil attributes:nil] )
    {
        MYLOG(@"SingleFileDownloader#newFileWithName: %@ created OK!", myFilePath);
    }
    else
    {
        MYLOG(@"SingleFileDownloader#newFileWithName: %@ creation FAILED!", myFilePath);
        return nil;
    }
    
    return [NSFileHandle fileHandleForWritingAtPath: myFilePath];
}


+ (id) fileDownloaderWithSourcePath: (NSString *) sourcePath targetFilename: (NSString *) aTargetFilename delegate: (id<SingleFileDownloaderDelegate>) aDelegate
{
    return [ [ [self alloc] initWithSourcePath:sourcePath targetFilename: aTargetFilename delegate:aDelegate ] autorelease ];
}

- (id) initWithSourcePath: (NSString *) sourcePath targetFilename: (NSString *) aTargetFilename delegate: (id<SingleFileDownloaderDelegate>) aDelegate
{
    if ( (self = [super init]) )
    {
        _connection = nil;
        _filename = [ aTargetFilename retain];
        _sourcePath = [ sourcePath retain];
        
        _bytesReceived = 0;
        _bytesTotal = 0;
        _delegate = aDelegate;
        
        _fileHandle = [ [SingleFileDownloader newFileWithName: _filename] retain];
    }
    
    return self;
}

- (void) dealloc
{
    MYLOG(@"SingleFileDownloader#dealloc");
    
    if ( _downloading )
        [self cancelDownload];
    
    [_connection release];
    [_filename release];
    [_sourcePath release];
    [_fileHandle release];
    
    [super dealloc];
}

- (void) startDownload
{
    if ( [ [NSFileManager defaultManager] fileExistsAtPath: [self targetPath] ] )
    {
        MYLOG(@"SingleFileDownloader#startDownload file already downloaded and exist at %@", [self targetPath]);
        [self cancelDownload];
        
        NSDictionary *dict = [ [NSFileManager defaultManager] attributesOfItemAtPath: [self targetPath] error: NULL];
        if (dict)
        {
            NSNumber *sizeOfFile = [dict valueForKey: NSFileSize];
            _bytesTotal = _bytesReceived = [sizeOfFile intValue];
            [_delegate downloadSizeUpdated];
        }
        else
            MYLOG(@"SingleFileDownloader#startDownload exists, but no dict for attr!");
        
        [ _delegate downloadFinished ];
        return;
    }
    
    MYLOG(@"SingleFileDownloader#startDownload URL= %@", _sourcePath);
    NSURLRequest *request = [NSURLRequest requestWithURL: [NSURL URLWithString: _sourcePath]
                                             cachePolicy: NSURLRequestUseProtocolCachePolicy
                                         timeoutInterval: fileDownloaderDefaultTimeout];
    
    _connection = [ [NSURLConnection connectionWithRequest: request delegate: self] retain];
    
    NSString *err = nil;
    
    if ( !_connection )
    {
        err = @"Can't open connection";
    } else if ( !_fileHandle)
        {
            err = @"Can't create file";
        }
    
    if ( err )
    {
        MYLOG(@"SingleFileDownloader#startDownload download failed with error: %@!", err);
        [_delegate downloadFailedWithError: err];
        return;
    }
    
    _downloading = YES;
    MYLOG(@"SingleFileDownloader#startDownload download started!");
    
}

- (void) cancelDownload
{
    MYLOG(@"SingleFileDownloader#cancelDownload %@ download cancelled",_sourcePath);
    
    _downloading = NO;
    
    // close connection and file
    if (_connection)
    {
        [_connection cancel];
        [_connection release];
    }
    
    if ( _fileHandle )
        [_fileHandle closeFile];
    
    // delete tmp file
    NSString *tmpPath = [NSString stringWithFormat:@"%@/%@%@", [SingleFileDownloader destinationDirectoryPath], _filename, [SingleFileDownloader tmpSuffix]];
    [[NSFileManager defaultManager] removeItemAtPath: tmpPath error: NULL];
    
    _connection = nil;
    [_fileHandle release];
    _fileHandle = nil;    
    //_bytesReceived = 0;    
}

- (NSString *) targetPath
{
    return [NSString stringWithFormat:@"%@/%@", [SingleFileDownloader destinationDirectoryPath], _filename];
}

- (NSUInteger) contentDownloaded
{
    return _bytesReceived;
}

- (NSUInteger) contentLength
{
    return _bytesTotal;
}


#pragma mark NSURLConnection Delegate Methods
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    _bytesReceived = 0;
    _bytesTotal = [response expectedContentLength];
    
    //test for free space
    NSDictionary *fsAttributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[self targetPath] error: NULL];
    unsigned long long freeSpace = [ [fsAttributes objectForKey:NSFileSystemFreeSize] unsignedLongLongValue ];
    
    if ( freeSpace && ( freeSpace <= _bytesTotal )  )
    {
        MYLOG(@"Not Enough Space detected!");
        NSString *err = @"Not enough space";
        [_delegate downloadFailedWithError: err];
        [self cancelDownload];
        return;
    }
    
    
    [_delegate downloadSizeUpdated];
    
    MYLOG(@"SingleFileDownloader#connection: %@ didReceiveResponse: %@", connection,  response);
}


- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
    MYLOG(@"SingleFileDownloader#connection: %@ willSendRequest: %@ redirectResponse: %@", connection, request,  response );
    
    if (response)
    {
        MYLOG(@"Redirect Detected!");
        NSString *err = @"Unhandled redirect";
        [_delegate downloadFailedWithError: err ];
        [self cancelDownload];
        return nil;
    }
    
    return request;
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    _bytesReceived += [data length];
    
    MYLOG(@"SingleFileDownloader#connection:%@ did receive data: [%d] Progress: %d/%d", 
          connection,
          (int)[data length],
          (int)_bytesReceived, 
          (int)_bytesTotal     );
    

    
    [_fileHandle seekToEndOfFile];
    [_fileHandle writeData: data];
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSError *error = nil;
    
    [_fileHandle closeFile];
    
    //rename ready file
    NSString *tmpPath = [ SingleFileDownloader tmpPathWithFilename: _filename ];
    NSString *destPath = [self targetPath];
    if ( ! [ [NSFileManager defaultManager] moveItemAtPath: tmpPath toPath: destPath error: &error] )
    {
        [self cancelDownload];
        
        MYLOG(@"SingleFileDownloader#connectionDidFinishLoading FAILED: %@ Description: %@", 
              [error localizedFailureReason], [error localizedDescription] );
        
        NSString *errString = [error localizedDescription];
        
        [ _delegate downloadFailedWithError: errString ];
        
        return;
    }
    
    [self cancelDownload];
    [_delegate downloadFinished];
    MYLOG(@"SingleFileDownloader#connectionDidFinishLoading: %@", connection );
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    MYLOG(@"SingleFileDownloader#connectionDidFailWithError: %@ Description: %@", [error localizedFailureReason], [error localizedDescription]);
    
    [self cancelDownload];
    
    //[_delegate downloadFailedWithError: [error localizedDescription] ];
    [_delegate downloadFailedWithError: @"Connection Error" ];
}



@end