//
//  TMXGenerator.m
//  AutoGenTest
//
//  Created by Jeremy on 3/19/11.
//
/*
 Copyright (c) 2011 Stone Software, Jeremy Stone. All rights reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "TMXGenerator.h"
#import "LFCGzipUtility.h"
#import "cencode.h"


@interface TMXGenerator ()
- (void) addMapAttributesWithPath:(NSString*)inPath width:(int)width height:(int)height tileWidth:(int)widthInPixels tileHeight:(int)heightInPixels orientation:(NSString*)orientation;
- (void) addLayerNamed:(NSString*)layerName width:(int)width height:(int)height data:(NSData*)binaryLayerData visible:(BOOL)isVisible;
- (BOOL) addTilesetWithImage:(NSString*)imgName named:(NSString*)name width:(int)width height:(int)height tileSpacing:(int)spacing tileProperties:(NSDictionary*)properties;
- (void) addObjectGroupNamed:(NSString*)name width:(int)width height:(int)height objectList:(NSArray*)objects;
@end


@implementation TMXGenerator

@synthesize delegate = delegate_;


- (id) init
{
	self = [super init];
	if (self != nil)
	{
		highestGID = 0;
		tileSets = nil;
		path = nil;
		mapAttributes = nil;
		layers = nil;
		delegate_ = nil;
	}
	return self;
}


- (void) dealloc
{
	[tileSets release];
	[mapAttributes release];
	[layers release];
	[path release];
	[copiedAtlasNames release];
	[objectGroups release];

	[delegate_ release];
	
	[super dealloc];
}


#pragma mark -


- (void) addMapAttributesWithPath:(NSString*)inPath width:(int)width height:(int)height tileWidth:(int)widthInPixels tileHeight:(int)heightInPixels orientation:(NSString*)orientation
{
	if (mapAttributes)
		[mapAttributes release];
	mapAttributes = [[NSMutableDictionary alloc] initWithCapacity:5];
	[mapAttributes setObject:[NSString stringWithFormat:@"%i", width] forKey:kHeaderInfoMapWidth];
	[mapAttributes setObject:[NSString stringWithFormat:@"%i", height] forKey:kHeaderInfoMapHeight];
	[mapAttributes setObject:[NSString stringWithFormat:@"%i", widthInPixels] forKey:kHeaderInfoMapTileWidth];
	[mapAttributes setObject:[NSString stringWithFormat:@"%i", heightInPixels] forKey:kHeaderInfoMapTileHeight];
	if (orientation)
		[mapAttributes setObject:orientation forKey:kHeaderInfoMapOrientation];

	if (path)
		[path release];
	path = [[NSString alloc] initWithString:inPath];
}


/*
 binary layer data is filled with GID's (unsigned int each), coords going left top to right
 bottom.  i.e. (0,0) (1,0) (2,0) (3,0) (0,1) (1,1) (2,1) (3,1) (0,2) (1,2) (2,2) (3,2)...
 see this link:  http://sourceforge.net/apps/mediawiki/tiled/index.php?title=Examining_the_map_format
*/
- (void) addLayerNamed:(NSString*)layerName width:(int)width height:(int)height data:(NSData*)binaryLayerData visible:(BOOL)isVisible
{
	NSDictionary* dict = [TMXGenerator layerNamed:layerName width:width height:height data:binaryLayerData visible:isVisible];
	
	if (!layers)
		layers = [[NSMutableArray alloc] initWithCapacity:10];
	[layers addObject:dict];
}


/*
	add a new tileset to our class.
 
	Properties are individual tile properties and are in standard dictionary key-value format.
	They are indexed by tile offset.  So the top-left tile in your designated tile atlas would be 
	tile 0, tile 1 would be the tile just to the right of tile 0 and so forth, wrapping at the 
	right edge of the tile.  
	
	**NOTE: values need to be NSStrings for these properties!
*/
- (BOOL) addTilesetWithDictionary:(NSDictionary*)tileAttributes tileProperties:(NSDictionary*)properties
{
	highestGID++;
	
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:tileAttributes];
	[dict setObject:[NSString stringWithFormat:@"%i", highestGID] forKey:kTilesetGIDStart];
	
	// add properties
	if (properties)
	{
		[dict setObject:properties forKey:kTileProperties];
	}
	
	// figure out the highest GID possible and set our max GIDs used for the next possible texture map
	UIImage* img = [UIImage imageNamed:[dict objectForKey:kTileSetImageAtlasFilename]];
	if (img)
	{
		int width = [[dict objectForKey:kImageAtlasTileWidth] intValue];
		int height = [[dict objectForKey:kImageAtlasTileHeight] intValue];
		int spacing = [[dict objectForKey:kImageAtlasTileSpacing] intValue];
		
		int across = img.size.width / (width + spacing);
		int down = img.size.height / (height + spacing);
		highestGID += across * down + 10;

		// add the dictionary to our tileset list.
		if (!tileSets)
			tileSets = [[NSMutableDictionary alloc] initWithCapacity:20];
		
		NSString* name = [dict objectForKey:kTileSetName];
		if (name)
			[tileSets setObject:dict forKey:name];
		else 
			return NO;

		return YES;
	}
	
	return NO;
}


// helper function, turns out I would rather pass in a dictionary, but this may prove helpful later...
- (BOOL) addTilesetWithImage:(NSString*)imgName named:(NSString*)name width:(int)width height:(int)height tileSpacing:(int)spacing tileProperties:(NSDictionary*)properties
{
	NSDictionary* dict = [TMXGenerator tileSetWithImage:imgName named:name width:width height:height tileSpacing:spacing];
	return [self addTilesetWithDictionary:dict tileProperties:properties];
}


/*
	the objects variable should have > 0 objects in it.  Valid object keys include:
	"name", "x", "y", "width", "height", "type", and an array of key/value entries named "properties" (with the keys "name" and "value").
 
	Example:
	<objectgroup name="Object Layer 1" width="32" height="32">
		... // object here
	</objectgroup>
*/
- (void) addObjectGroupNamed:(NSString*)name width:(int)width height:(int)height objectList:(NSArray*)objects
{
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:10];
	if (!objectGroups)
		objectGroups = [[NSMutableArray alloc] initWithCapacity:10];
	
	[dict setObject:name forKey:kObjectGroupName];
	[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kObjectGroupWidth];
	[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kObjectGroupHeight];
	[dict setObject:objects forKey:kObjectGroupProperties];
	
	[objectGroups addObject:dict];
}


- (NSString*) tileIDFromTileSet:(NSDictionary*)tileset thatMatchesKey:(NSString*)tileKeyVal property:(NSString*)tilePropertyVal
{
	NSDictionary* properties = [tileset objectForKey:kTileProperties];
	if (properties)
	{
		for (id propertyKey in [properties allKeys])
		{
			NSDictionary* dict = [properties objectForKey:propertyKey];
			if ([dict objectForKey:tileKeyVal])
			{
				NSString* str = [dict objectForKey:tileKeyVal];
				if ([tilePropertyVal isEqualToString:str])
					return propertyKey;
			}
		}
	}
	
	return nil;
}


#pragma mark -


+ (NSString*) propertiesToXML:(NSDictionary*)properties
{
	NSMutableString* retVal = [NSMutableString string];
	if (!properties)
		return retVal;
	
	[retVal appendString:@"<properties>\r"];
	for (NSString* valueKey in [properties allKeys])
	{
		[retVal appendFormat:@"<property name=\"%@\" value=\"%@\"/>\r", valueKey, [properties objectForKey:valueKey]];
	}
	[retVal appendString:@"</properties>\r"];
	
	return retVal;
}


+ (NSString*) objectGroupsToXML:(NSArray*)groups
{
	NSMutableString* retVal = [NSMutableString string];
	
	// convert the passed in array to an array of objects XML.
	for (NSDictionary* group in groups)
	{
		[retVal appendFormat:@"<objectgroup name=\"%@\" width=\"%@\" height=\"%@\">\r", [group objectForKey:kObjectGroupName], [group objectForKey:kObjectGroupWidth], [group objectForKey:kObjectGroupHeight]];
		NSArray* objects = [group objectForKey:kObjectGroupProperties];
		for (NSDictionary* dict in objects)
		{
			[retVal appendFormat:@"<object name=\"%@\"", [dict objectForKey:kGroupObjectName]];
			if ([dict objectForKey:kGroupObjectType])
				[retVal appendFormat:@" type=\"%@\"", [dict objectForKey:kGroupObjectType]]; 
			if ([dict objectForKey:kGroupObjectX])
				[retVal appendFormat:@" x=\"%@\"", [dict objectForKey:kGroupObjectX]];
			if ([dict objectForKey:kGroupObjectY])
				[retVal appendFormat:@" y=\"%@\"", [dict objectForKey:kGroupObjectY]];
			if ([dict objectForKey:kGroupObjectWidth])
				[retVal appendFormat:@" width=\"%@\"", [dict objectForKey:kGroupObjectWidth]];
			if ([dict objectForKey:kGroupObjectHeigth])
				[retVal appendFormat:@" height=\"%@\"", [dict objectForKey:kGroupObjectHeigth]];
			[retVal appendString:@">\r"];
			
			if ([dict objectForKey:kGroupObjectProperties])
				[retVal appendString:[TMXGenerator propertiesToXML:[dict objectForKey:kGroupObjectProperties]]];

			[retVal appendString:@"</object>"];
		}
		
		[retVal appendString:@"</objectgroup>\r"];
	}
	
	return retVal;
}


+ (NSString*) layersToXML:(NSArray*)inLayers
{
	NSMutableString* retVal = [NSMutableString string];

	// convert the passed in array to an array of layer XML.
	for (NSDictionary* dict in inLayers)
	{
		// this will be where we zip and encode layers.
		// layers should be dictionaries.
//		if ([dict objectForKey:kLayerIsVisible])		// making the layer invisible causes the TMX map to not load it!  :/
//			[retVal appendFormat:@"<layer name=\"%@\" width=\"%@\" height=\"%@\" visible=\"%@\">\r", [dict objectForKey:kLayerName], [dict objectForKey:kLayerWidth], [dict objectForKey:kLayerHeight], [dict objectForKey:kLayerIsVisible]];
//		else 
			[retVal appendFormat:@"<layer name=\"%@\" width=\"%@\" height=\"%@\">\r", [dict objectForKey:kLayerName], [dict objectForKey:kLayerWidth], [dict objectForKey:kLayerHeight]];
		[retVal appendString:@"<data encoding=\"base64\" compression=\"gzip\">\r"];
		
		NSData *bufferData = [dict objectForKey:kLayerData];
		NSData *data = [LFCGzipUtility gzipData:bufferData];
		NSUInteger len = [data length];
		char* byteData = (char*)malloc(len);
		memcpy(byteData, [data bytes], len);
		char* encodedStr = base64_encode(byteData, len);
		
		[retVal appendFormat:@"%s\r</data>\r", encodedStr];
		
		// rotation XML.  See http://www.cocos2d-iphone.org/forum/topic/16552
		[retVal appendString:@"<rotation_data encoding=\"base64\" compression=\"gzip\">\r"];
		
		bufferData = [dict objectForKey:kLayerRotationData];
		data = [LFCGzipUtility gzipData:bufferData];
		len = [data length];
		byteData = (char*)malloc(len);
		memcpy(byteData, [data bytes], len);
		encodedStr = base64_encode(byteData, len);
		[retVal appendFormat:@"%s\r</rotation_data>\r", encodedStr];
		
		
		[retVal appendString:@"</layer>\r"];
		free(encodedStr);
		free(byteData);
	}
	
	return retVal;
}

/*
	 Attributes include:
		 kImageAtlasTileWidth		(width)
		 kImageAtlasTileHeight		(height)
		 kImageAtlasTileSpacing		(tiles are spaced apart this amount of pixels in the atlas image)
		 kTilesetGIDStart			(first GID used in the tileset)
		 kTileSetName				(tileset name)
		 kTileSetImageAtlasFilename (filename of image atlas)
 
 example tileset XML:
 
 <tileset firstgid="1" name="Test Tileset" tilewidth="32" tileheight="32" spacing="2">
	 <image source="regularTiles_default.png"/>
	 <tile id="0">
		 <properties>
			 <property name="Grass Property" value=""/>
			 <property name="type" value="1"/>
		 </properties>
	 </tile>
	 <tile id="8">
		 <properties>
			 <property name="ocean" value=""/>
			 <property name="type" value="1"/>
		 </properties>
	 </tile>
 </tileset>
 
*/
+ (NSString*) tileSetsToXML:(NSDictionary*)inTileSets
{
	NSMutableString* retVal = [NSMutableString string];

	// iterate through each key and generate a tileset named the same as the key name of the dictionary for the tilesets.
	NSArray* keys = [inTileSets allKeys];
	for (id key in keys)
	{
		NSDictionary* dict = [inTileSets objectForKey:key];
		if (dict)
		{
			[retVal appendFormat:@"<tileset firstgid=\"%i\"", [[dict objectForKey:kTilesetGIDStart] intValue]];
			[retVal appendFormat:@" name=\"%@\"", [dict objectForKey:kTileSetName]];
			[retVal appendFormat:@" tilewidth=\"%i\"", [[dict objectForKey:kImageAtlasTileWidth] intValue]];
			[retVal appendFormat:@" tileheight=\"%i\"", [[dict objectForKey:kImageAtlasTileHeight] intValue]];
			[retVal appendFormat:@" spacing=\"%i\"", [[dict objectForKey:kImageAtlasTileSpacing] intValue]];
			[retVal appendString:@">\r"];
			[retVal appendFormat:@"<image source=\"%@\"/>\r", [dict objectForKey:kTileSetImageAtlasFilename]];
			
			// properties
			NSDictionary* properties = [dict objectForKey:kTileProperties];
			if (properties)
			{
				for (id propertyKey in [properties allKeys])
				{
					[retVal appendFormat:@"<tile id=\"%@\">\r", propertyKey];
					[retVal appendString:[TMXGenerator propertiesToXML:[properties objectForKey:propertyKey]]];
					[retVal appendString:@"</tile>\r"];
				}
			}
			
			[retVal appendString:@"</tileset>\r"];
		}
	}

	return retVal;
}


//////// writeTMXFile ///////
/*
	mapAttributes is a dictionary with the following attributes:
		kHeaderInfoMapWidth			- how many tiles wide
		kHeaderInfoMapHeight		- how many tiles high
		kHeaderInfoMapTileWidth		- tile width in pixels
		kHeaderInfoMapTileHeight	- tile height in pixels
 
	optional:
		kHeaderInfoMapOrientation	- tile orientation, default is @"orthogonal", @"isometric" also supported by cocos2d
 
	tileSets is a dictionary of named tilesets (dictionaries of tileset attributes, including properties)
 
	layers is an NSArray of layer information dictionaries.
*/
+ (void) writeTMXFileWithName:(NSString*)filePath mapAttributes:(NSDictionary*)mapAttributes tilesets:(NSDictionary*)inTileSets layers:(NSArray*)inLayers objectGroups:(NSArray*)inObjectGroups
{
	NSMutableString* outStr = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r<!DOCTYPE map SYSTEM \"http://mapeditor.org/dtd/1.0/map.dtd\">\r"];

	// map header details
	NSString* orientation = @"orthogonal";
	if ([mapAttributes objectForKey:kHeaderInfoMapOrientation])
		orientation = [mapAttributes objectForKey:kHeaderInfoMapOrientation];
	[outStr appendFormat:@"<map version=\"1.0\" orientation=\"%@\" ", orientation];
	
	// width and height (for now always square)
	int width = [[mapAttributes objectForKey:kHeaderInfoMapWidth] intValue];
	int height = [[mapAttributes objectForKey:kHeaderInfoMapHeight] intValue];
	[outStr appendFormat:@"width=\"%i\" height=\"%i\" ", width, height];
	
	// tile width and height for map
	int tileWidth = [[mapAttributes objectForKey:kHeaderInfoMapTileWidth] intValue];
	int tileHeight = [[mapAttributes objectForKey:kHeaderInfoMapTileHeight] intValue];
	[outStr appendFormat:@"tilewidth=\"%i\" tileheight=\"%i\">\r", tileWidth, tileHeight];
	
	// append the tilesets
	[outStr appendString:[TMXGenerator tileSetsToXML:inTileSets]];
	
	// append the layers
	[outStr appendString:[TMXGenerator layersToXML:inLayers]];
	
	// append the object groups
	[outStr appendString:[TMXGenerator objectGroupsToXML:inObjectGroups]];
	
	// close map tag
	[outStr appendString:@"\r</map>"];
	
	[outStr writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}


#pragma mark -
#pragma mark helper functions

// create layer information.
// binaryLayerData can be nil
+ (NSDictionary*) layerNamed:(NSString*)layerName width:(int)width height:(int)height data:(NSData*)binaryLayerData visible:(BOOL)isVisible
{
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:4];
	[dict setObject:layerName forKey:kLayerName];
	[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kLayerWidth];
	[dict setObject:[NSString stringWithFormat:@"%i", height] forKey:kLayerHeight];
	if (isVisible == NO)
		[dict setObject:@"0" forKey:kLayerIsVisible];
	if (binaryLayerData)
		[dict setObject:binaryLayerData forKey:kLayerData];
	return dict;
}


+ (NSDictionary*) tileSetWithImage:(NSString*)imgName named:(NSString*)name width:(int)width height:(int)height tileSpacing:(int)spacing 
{
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:20];
	
	[dict setObject:imgName forKey:kTileSetImageAtlasFilename];
	[dict setObject:name forKey:kTileSetName];
	[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kImageAtlasTileWidth];
	[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kImageAtlasTileHeight];
	[dict setObject:[NSString stringWithFormat:@"%i", spacing] forKey:kImageAtlasTileSpacing];
	
	return dict;
}


/*
 Object Groups contain objects (non-tile entities).  These can represent things like triggers, spawn points, etc.
 Name, x and y value required.
 Example:
 <object name="asdf" type="whee" x="484" y="283" width="45" height="46">
 <properties>
 <property name="property1" value="prop"/>
 </properties>
 </object>
 */
+ (NSDictionary*) makeGroupObjectWithName:(NSString*)name type:(NSString*)type x:(int)x y:(int)y width:(int)width height:(int)height properties:(NSDictionary*)properties
{
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:10];
	
	[dict setObject:name forKey:kGroupObjectName];
	[dict setObject:[NSString stringWithFormat:@"%i", x] forKey:kGroupObjectX];
	[dict setObject:[NSString stringWithFormat:@"%i", y] forKey:kGroupObjectY];
	if (type)
		[dict setObject:type forKey:kGroupObjectType];
	if (width)
		[dict setObject:[NSString stringWithFormat:@"%i", width] forKey:kGroupObjectWidth];
	if (height)
		[dict setObject:[NSString stringWithFormat:@"%i", height] forKey:kGroupObjectHeigth];
	if (properties)
		[dict setObject:properties forKey:kGroupObjectProperties];
	
	return dict;
}


#pragma mark -


- (BOOL) generateTMXMap:(NSError**)error;
{
	if (!delegate_)
		return NO;
	
	NSDictionary* mapInfo = [delegate_ mapSetupInfo];
	if (!mapInfo)
	{
		if (error)
			*error = [[NSError alloc] initWithDomain:@"Unable to get basic map info when calling delegate method mapSetupInfo" code:0 userInfo:nil];
		return NO;
	}

	int mapWidth = [[mapInfo objectForKey:kHeaderInfoMapWidth] intValue];
	int mapHeight = [[mapInfo objectForKey:kHeaderInfoMapHeight] intValue];
		
	NSArray* tileSetNames = [delegate_ tileSetNames];
	if (!tileSetNames || ![tileSetNames count])
	{
		if (error)
			*error = [[NSError alloc] initWithDomain:@"Unable to get any tileset names when calling delegate method tileSetNames" code:0 userInfo:nil];
		return NO;
	}
	
	// add our tilesets
	NSString* key;
	for (key in tileSetNames)
	{
		NSDictionary* dict = [delegate_ tileSetInfoForName:key];
		if (!dict)
		{
			if (error)
				*error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unable to get tileset from name %@ when calling delegate method tileSetInfoForName:", key] code:0 userInfo:nil];
			return NO;
		}

		NSDictionary* properties = nil;
		if ([delegate_ respondsToSelector:@selector(propertiesForTileSetNamed:)])
			properties = [delegate_ propertiesForTileSetNamed:key];
		if (!properties)
		{
			if (error)
				*error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unable to get properties from tileset name %@ when calling delegate method propertiesForTileSetNamed:", key] code:0 userInfo:nil];
			return NO;
		}
		
		[self addTilesetWithDictionary:dict tileProperties:properties];
	}

	NSArray* layerNames = [delegate_ layerNames];
	if (!layerNames || ![layerNames count])
	{
		if (error)
			*error = [[NSError alloc] initWithDomain:@"Unable to get any layer names when calling delegate method layerNames" code:0 userInfo:nil];
		return NO;
	}
	
	// add our layers
	NSString* tilePropertyVal;
	NSString* tileKeyVal;
	for (key in layerNames)
	{
		NSDictionary* dict = [delegate_ layerInfoForName:key];
		if (!dict)
		{
			if (error)
				*error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unable to get layer from name %@ when calling delegate method layerInfoForName:", key] code:0 userInfo:nil];
			return NO;
		}
		
		tileKeyVal = [delegate_ tileIdentificationKeyForLayer:key];

		unsigned int mapData[mapHeight][mapWidth];
		BOOL hasData = NO;
		
		for (int y = 0; y < mapHeight; y++)
		{
			for (int x = 0;  x < mapWidth; x++)
			{
				// get the tileset name and the appropriate property to look for within that tileset.
				NSString* tileSetName = [delegate_ tileSetNameForLayer:key];
				tilePropertyVal = [delegate_ tilePropertyForLayer:key tileSetName:tileSetName X:x Y:y];
				
				// find the tileset and then look through it to find the property key/value pair we are after.
				NSDictionary* tileSetForLayer = [tileSets objectForKey:tileSetName];
				int GID = [[tileSetForLayer objectForKey:kTilesetGIDStart] intValue];
				NSString* tempStr = [self tileIDFromTileSet:tileSetForLayer thatMatchesKey:tileKeyVal property:tilePropertyVal];
				if (tempStr)
					GID += [tempStr intValue];
				else 
					GID = 0;				// default to nothing if not found.
				
				mapData[y][x] = GID;		// TMX Maps stored different.
				if (GID)
					hasData = YES;
			}
		}

		if (hasData)	// skip this if it's a blank layer.
		{
			NSData* data = [NSData dataWithBytes:mapData length:sizeof(unsigned int) * mapWidth * mapHeight];
			NSMutableDictionary* dictToAdd = [NSMutableDictionary dictionaryWithDictionary:dict];
			[dictToAdd setObject:data forKey:kLayerData];
			
			// rotation data in addition to map data.
			if ([delegate_ respondsToSelector:@selector(tileRotationForLayer:X:Y:)])
			{
				unsigned int rotationData[mapHeight][mapWidth];
				
				for (int y = 0; y < mapHeight; y++)
				{
					for (int x = 0;  x < mapWidth; x++)
					{
						rotationData[y][x] = [delegate_ tileRotationForLayer:key X:x Y:y];
					}
				}
				
				NSData* data = [NSData dataWithBytes:rotationData length:sizeof(unsigned int) * mapWidth * mapHeight];
				[dictToAdd setObject:data forKey:kLayerRotationData];
			}
			
			if (!layers)
				layers = [[NSMutableArray alloc] initWithCapacity:10];
			[layers addObject:dictToAdd];
		}
	}
	
	NSArray* groups = [delegate_ objectGroupNames];
	if (groups && [groups count])	// object groups are optional, so don't throw an error if there are none just skip them.
	{
		for (key in groups)
		{
			NSMutableArray* results = [NSMutableArray arrayWithCapacity:10];
			NSArray* objects = [delegate_ objectInfoForName:key];
			for (NSDictionary* dict in objects)
			{
				if (!dict)
				{
					if (error)
						*error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unable to get object group from name %@ when calling delegate method objectInfoForName:", key] code:0 userInfo:nil];
					return NO;
				}
				
				// add the properties if they are defined
				NSArray* properties = nil;
				if ([delegate_ respondsToSelector:@selector(propertiesForObjectGroupNamed:objectName:)])
				{
					properties = [delegate_ propertiesForObjectGroupNamed:key objectName:[dict objectForKey:kGroupObjectName]];
					if (properties)
					{
						NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithCapacity:[dict count] + 1];
						[tempDict addEntriesFromDictionary:dict];
						[tempDict setObject:properties forKey:kGroupObjectProperties];
						dict = [NSDictionary dictionaryWithDictionary:tempDict];
					}
				}
				
				if (dict)
					[results addObject:dict];
			}
			
			[self addObjectGroupNamed:key width:mapWidth height:mapHeight objectList:results];
		}
	}

	// create the TMX file on disk.
	NSString* mapPath = [delegate_ mapFilePath];
	[TMXGenerator writeTMXFileWithName:mapPath
						 mapAttributes:mapInfo
							  tilesets:tileSets 
								layers:layers 
						  objectGroups:objectGroups];
	
	// copy the image atlas to the written path from the main bundle.  We can change this later as needed to copy/move from a different source.
	if (!copiedAtlasNames)
		copiedAtlasNames = [[NSMutableSet alloc] initWithCapacity:10];

	NSString* pathForDest = [mapPath stringByDeletingLastPathComponent];
	for (NSString* tileKey in tileSets)
	{
		NSDictionary* dict = [tileSets objectForKey:tileKey];
		NSString* fileName = [dict objectForKey:kTileSetImageAtlasFilename];
		NSString* destPath = [pathForDest stringByAppendingPathComponent:fileName];
		if (![copiedAtlasNames containsObject:fileName])
		{
			[[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
			if (![[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:[fileName stringByDeletingPathExtension] ofType:[fileName pathExtension]] toPath:destPath error:error])
			{	
				if (error)
					*error = [[NSError alloc] initWithDomain:[NSString stringWithFormat:@"Unable to copy atlas to %@ with name %@ after creating the map", pathForDest, fileName] code:0 userInfo:nil];
				return NO;
			}
			[copiedAtlasNames addObject:fileName];
		}
	}
	
	return YES;
}


// using this class inline.  Problem with this is that it isn't terribly flexible, but is a good example if you don't want to use the delegate for some reason.
- (void) saveSampleMapWithPath:(NSString*)inPath
{
	int width = 16;
	int height = 16;

	// add map attributes
	[self addMapAttributesWithPath:inPath width:width height:height tileWidth:32 tileHeight:32 orientation:nil];

	// add a tileset
	[self addTilesetWithImage:@"regularTiles_default.png" named:@"Default Tileset" width:32 height:32 tileSpacing:2 tileProperties:nil];

	// fill in the GIDs
	// should we use a delegate here, make this more generic?  Thinking we should...
	arc4random_stir();
	unsigned int gids[width][height];
	for (int x = 0; x < height; x++)
	{
		for (int y = 0; y < width; y++)
		{
			gids[x][y] = arc4random() % 3 + 1;		// one of 3 different tiles, grass, hills or dirt.
		}
	}
	
	NSData* data = [NSData dataWithBytes:gids length:sizeof(unsigned int)*width*height];
	
	// add a layer
	[self addLayerNamed:@"Background" width:width height:height data:data visible:YES];
	
	// add a spawn point object and an object layer
	NSDictionary* dict = [TMXGenerator makeGroupObjectWithName:@"SpawnPoint" type:nil x:50 y:50 width:0 height:0 properties:[NSDictionary dictionaryWithObject:@"This is a property string" forKey:@"somePropertyKey"]];
	[self addObjectGroupNamed:@"Object Layer" width:width height:height objectList:[NSArray arrayWithObject:dict]];
	
	// convert to XML
	// save as file
	[TMXGenerator writeTMXFileWithName:path mapAttributes:mapAttributes tilesets:tileSets layers:layers objectGroups:objectGroups];
}


@end
