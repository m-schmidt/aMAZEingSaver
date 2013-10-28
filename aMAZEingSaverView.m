// aMAZEingSaverView.m
// A port of xlockmore's maze mode to OS X
//
// OS X Port Copyright (C) 2006 Michael Schmidt <mschmidt.github@gmail.com>.
//
// Permission to use, copy, modify, and distribute this software and its
// documentation for any purpose and without fee is hereby granted,
// provided that the above copyright notice appear in all copies and that
// both that copyright notice and this permission notice appear in
// supporting documentation.
//
// This file is provided AS IS with no warranties of any kind.  The author
// shall have no liability with respect to the infringement of copyrights,
// trade secrets or any patents by this file or any part thereof.  In no
// event will the author be liable for any lost revenue or profits or
// other special, indirect and consequential damages.



/* Original xlockmore copyright:
 *
 * Copyright (c) 1988 by Sun Microsystems
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose and without fee is hereby granted,
 * provided that the above copyright notice appear in all copies and that
 * both that copyright notice and this permission notice appear in
 * supporting documentation.
 *
 * This file is provided AS IS with no warranties of any kind.  The author
 * shall have no liability with respect to the infringement of copyrights,
 * trade secrets or any patents by this file or any part thereof.  In no
 * event will the author be liable for any lost revenue or profits or
 * other special, indirect and consequential damages.
 *
 * Revision History:
 * 27-Nov-2001: interactive maze mode Ephraim Yawitz fyawitz@actcom.co.il
 * 01-Nov-2000: Allocation checks
 * 27-Oct-1997: xpm and ras capability added
 * 10-May-1997: Compatible with xscreensaver
 * 27-Feb-1996: Add ModeInfo args to init and callback hooks, use new
 *              ModeInfo handle to specify long pauses (eliminate onepause).
 *		        Ron Hitchens <ron@idiom.com>
 * 20-Jul-1995: minimum size fix Peter Schmitzberger <schmitz@coma.sbg.ac.at>
 * 17-Jun-1995: removed sleep statements
 * 22-Mar-1995: multidisplay fix Caleb Epstein <epstein_caleb@jpmorgan.com>
 * 09-Mar-1995: changed how batchcount is used
 * 27-Feb-1995: patch for VMS
 * 04-Feb-1995: patch to slow down maze Heath Kehoe <hakehoe@icaen.uiowa.edu>
 * 17-Jun-1994: HP ANSI C compiler needs a type cast for gray_bits
 *              Richard Lloyd <R.K.Lloyd@csc.liv.ac.uk>
 * 02-Sep-1993: xlock version David Bagley <bagleyd@tux.org>
 * 07-Mar-1993: Good ideas from xscreensaver Jamie Zawinski <jwz@jwz.org>
 * 06-Jun-1985: Martin Weiss Sun Microsystems
 */



#import <stdlib.h>
#import "aMAZEingSaverView.h"


// Sizes in pixels
#define MIN_CELL_SIZE            8
#define MAX_CELL_SIZE           23
#define MAX_CELL_SIZE_PREVIEW   13
#define LOGO_SIZE              140
#define LOGO_SIZE_PREVIEW       52

// Delay times in frames
#define DELAY_SMALL            150
#define DELAY_BIG              300

// Within the created array we mark adjacent walls for each cell
#define WALL_BOTTOM         0x8000
#define WALL_RIGHT          0x4000
#define WALL_TOP            0x2000
#define WALL_LEFT           0x1000

// During creation of the maze we use door-bits to avoid running into cycles
#define DOOR_IN_ANY         0x0f00
#define DOOR_IN_BOTTOM      0x0800
#define DOOR_IN_RIGHT       0x0400
#define DOOR_IN_TOP         0x0200
#define DOOR_IN_LEFT        0x0100

#define DOOR_OUT_ANY        0x00f0
#define DOOR_OUT_BOTTOM     0x0080
#define DOOR_OUT_RIGHT      0x0040
#define DOOR_OUT_TOP        0x0020
#define DOOR_OUT_LEFT       0x0010

// Some cells have a special meaning
#define START_SQUARE             1
#define END_SQUARE               2
#define VISITED_SQUARE           4
#define INACTIVE_SQUARE          8

// Walking directions
#define DIR_NONE                -1
#define DIR_DOWN                 0
#define DIR_RIGHT                1
#define DIR_UP                   2
#define DIR_LEFT                 3

#define CELL(X,Y)  (maze[(X) * height + (Y)])
#define NRAND(X)   (random () % (X))


// An image containing the icon of Finder.app
static NSImage *logo = nil;


// Colors
static CGFloat black    [4] = { 0.0,  0.0,  0.0,  1.0 };
static CGFloat white    [4] = { 1.0,  1.0,  1.0,  1.0 };
static CGFloat active   [4] = { 0.96, 0.96, 0.96, 1.0 };
static CGFloat inactive [4] = { 0.55, 0.55, 0.55, 1.0 };



@interface aMAZEingSaverView (private)

- (void)createMazeWithFrame:(NSRect)frame;
- (void)clearMaze;
- (int)chooseDirectionForX:(int)X Y:(int)Y;
- (void)createWalls;

@end



@implementation aMAZEingSaverView


+ (void)initialize
{
    srandom (time (NULL));

    NSString *path   = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.finder"];
    NSBundle *bundle = [NSBundle bundleWithPath: path];

    // Preload finder icon
    logo = [[NSImage alloc] initWithContentsOfFile: [bundle pathForResource:@"Finder" ofType: @"icns"]];
}



- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)flag
{
    if ((self = [super initWithFrame:frame isPreview:isPreview]))
    {
        isPreview = flag;
        maze      = NULL;
        path      = NULL;

        [self createMazeWithFrame:frame];
        [self setAnimationTimeInterval:1/60.0];

        delayCounter = DELAY_SMALL;
    }

    return self;
}



- (void)dealloc
{
    if (maze)
        free (maze);

    if (path)
        free (path);
}



- (void)animateOneFrame
{
    path_t *top = &(path [pathLen]);
    int *cell   = &(CELL (top->x, top->y));

    int next_x, next_y, next_dir;


    // Delay phase: decrement delaycounter
    if (delayCounter > 0)
    {
        delayCounter --;

        // We are in the mid of the delay => switch to next maze and continue delay
        if (delayCounter == DELAY_SMALL)
        {
            if (isPreview == NO)
            {
                CGDisplayFadeReservationToken token;

                CGAcquireDisplayFadeReservation (3.0, &token);
                CGDisplayFade (token, 0.5, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0.0, 0.0, 0.0, true);

                [self display];

                CGDisplayFade (token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0.0, 0.0, 0.0, false);
                CGReleaseDisplayFadeReservation (token);
            }
            else
                [self setNeedsDisplay: YES];
        }
    }


    // Maze solved => create next maze and start delay
    else if (top->x == endX && top->y == endY)
    {
        [self createMazeWithFrame: [self frame]];
        delayCounter = DELAY_BIG;
    }


    // During solve proceed with the depth first search
    else
    {
        // Select direction for forward-step
        for (next_dir = DIR_DOWN; next_dir <= DIR_LEFT; next_dir++)
        {
            if ((*cell & (WALL_BOTTOM >> next_dir)) == 0)
            {
                next_x = top->x;
                next_y = top->y;

                switch (next_dir)
                {
                    case DIR_DOWN:  next_y -= 1; break;
                    case DIR_RIGHT: next_x += 1; break;
                    case DIR_UP:    next_y += 1; break;
                    case DIR_LEFT:  next_x -= 1; break;
                }

                if (0 <= next_x && next_x < width)
                    if (0 <= next_y && next_y < height)
                        if ((CELL (next_x, next_y) & VISITED_SQUARE) == 0)
                        {
                            CELL (next_x, next_y) |= VISITED_SQUARE;

                            pathLen += 1;
                            path [pathLen].x = next_x;
                            path [pathLen].y = next_y;
                            break;
                        }
            }
        }


        // No direction found => step back
        if (next_dir > DIR_LEFT)
        {
            next_x = top->x;
            next_y = top->y;

            *cell |= INACTIVE_SQUARE;
            pathLen -= 1;
        }


        // Redraw area around changed cell
        [self setNeedsDisplayInRect: NSMakeRect (baseX + (next_x * cellSize) - 4,
                                                 baseY + (next_y * cellSize) - 4,
                                                 cellSize + 8,
                                                 cellSize + 8)];
    }
}



- (BOOL)hasConfigureSheet
{
    return NO;
}



- (NSWindow*)configureSheet
{
    return nil;
}



#pragma mark -
#pragma mark Drawing the Maze



#define NSRect2CGRect(R) (CGRectMake ((R).origin.x, (R).origin.y, (R).size.width, (R).size.height))

#define LINE(X,Y,DX,DY) do                          \
{                                                   \
    CGContextBeginPath (cg_ctx);                    \
    px = (X);                                       \
    py = (Y);                                       \
    CGContextMoveToPoint (cg_ctx, px, py);          \
    CGContextAddLineToPoint (cg_ctx, px+DX, py+DY); \
    CGContextDrawPath (cg_ctx, kCGPathFillStroke);  \
} while (0)


- (void)drawRect:(NSRect)rect
{
    CGContextRef cg_ctx;
    CGColorSpaceRef cg_space;
    CGRect cg_rect;
    int redraw_x1, redraw_x2, redraw_y1, redraw_y2, x, y, cell;
    CGFloat px, py;


    // Drawing setup
    cg_ctx   = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    cg_space = CGColorSpaceCreateDeviceRGB ();
    CGContextSetFillColorSpace (cg_ctx, cg_space);

    cg_rect = NSRect2CGRect (rect);
    CGContextClipToRect (cg_ctx, cg_rect);
    CGContextSetFillColor (cg_ctx, black);
    CGContextFillRect (cg_ctx, cg_rect);

    CGContextSetLineCap (cg_ctx, kCGLineCapSquare);
    CGContextSetStrokeColor (cg_ctx, white);

    CGContextSetShouldAntialias (cg_ctx, NO);
    CGContextTranslateCTM (cg_ctx, baseX+0.5, baseY+0.5);


    // What must be redrawn
    redraw_x1 = (rect.origin.x - baseX) / cellSize;
    redraw_x2 = (rect.origin.x + rect.size.width - baseX) / cellSize + 1;
    if (redraw_x2 > width) redraw_x2 = width;

    redraw_y1 = (rect.origin.y - baseY) / cellSize;
    redraw_y2 = (rect.origin.y + rect.size.height - baseY) / cellSize + 1;
    if (redraw_y2 > height) redraw_y2 = height;

    for (x = redraw_x1; x < redraw_x2; x++)
        for (y = redraw_y1; y < redraw_y2; y++)
        {
            cell = CELL (x, y);

            if (y == 0 && cell & WALL_BOTTOM)
                LINE (x * cellSize, y * cellSize, cellSize-1, 0);

            if (x == 0 && cell & WALL_LEFT)
                LINE (x * cellSize, y * cellSize, 0, cellSize-1);

            if (cell & WALL_RIGHT)
                LINE ((x + 1) * cellSize, y * cellSize, 0, cellSize);

            if (cell & WALL_TOP)
                LINE (x * cellSize, (y + 1) * cellSize, cellSize, 0);


            if (cell & VISITED_SQUARE)
            {
                CGContextSetFillColor (cg_ctx, (cell & INACTIVE_SQUARE) ? inactive : active);

                cg_rect.origin.x   = x * cellSize + 2;
                cg_rect.origin.y   = y * cellSize + 2;
                cg_rect.size.width = cg_rect.size.height = cellSize - 4;

                switch (cell & DOOR_IN_ANY)
                {
                    case DOOR_IN_BOTTOM:
                        cg_rect.origin.y    -= 4;
                        cg_rect.size.height += 4;
                        break;

                    case DOOR_IN_RIGHT:
                        cg_rect.size.width  += 4;
                        break;

                    case DOOR_IN_TOP:
                        cg_rect.size.height += 4;
                        break;

                    case DOOR_IN_LEFT:
                        cg_rect.origin.x    -= 4;
                        cg_rect.size.width  += 4;
                        break;
                }

                CGContextFillRect (cg_ctx, cg_rect);
            }

            if (cell & (START_SQUARE | END_SQUARE))
            {
                CGContextSetFillColor (cg_ctx, active);

                cg_rect.origin.x   = x * cellSize + 2;
                cg_rect.origin.y   = y * cellSize + 2;
                cg_rect.size.width = cg_rect.size.height = cellSize - 4;

                switch ((cell & START_SQUARE) ? startDir : endDir)
                {
                    case DIR_DOWN:  cg_rect.origin.y -= 4; break;
                    case DIR_RIGHT: cg_rect.origin.x += 4; break;
                    case DIR_UP:    cg_rect.origin.y += 4; break;
                    case DIR_LEFT:  cg_rect.origin.x -= 4; break;
                }

                CGContextFillRect (cg_ctx, cg_rect);
            }
        }

    CGContextTranslateCTM (cg_ctx, -baseX-0.5, -baseY-0.5);
    CGContextSetShouldAntialias (cg_ctx, YES);


    // Draw the Finder logo
    if (logo)
    {
        NSSize iSize = [logo size];
        float  sSize = (isPreview) ? 48 : 128;

        NSRect logoRect = NSMakeRect (baseX + logoX * cellSize + (logoSize * cellSize - sSize) / 2,
                                      baseY + logoY * cellSize + (logoSize * cellSize - sSize) / 2,
                                      sSize,
                                      sSize);

        [logo drawInRect: logoRect
                fromRect: NSMakeRect (0, 0, iSize.width, iSize.height)
               operation: NSCompositeSourceOver
                fraction: 1.0];
    }

    CGColorSpaceRelease (cg_space);
}



#pragma mark -
#pragma mark Creating a Maze



- (void)createMazeWithFrame:(NSRect)frame
{
    if (isPreview)
    {
        cellSize = MIN_CELL_SIZE + NRAND (MAX_CELL_SIZE_PREVIEW - MIN_CELL_SIZE + 1);
        logoSize = (LOGO_SIZE_PREVIEW + cellSize - 1) / cellSize;
    }
    else
    {
        cellSize = MIN_CELL_SIZE + NRAND (MAX_CELL_SIZE - MIN_CELL_SIZE + 1);
        logoSize = (LOGO_SIZE + cellSize - 1) / cellSize;
    }

    width   = (int)(frame.size.width -  2) / cellSize;
    height  = (int)(frame.size.height - 2) / cellSize;

    baseX   = ((int)frame.size.width  - cellSize * width)  / 2;
    baseY   = ((int)frame.size.height - cellSize * height) / 2;

    maze    = realloc (maze, (sizeof (int)    * width * height));
    path    = realloc (path, (sizeof (path_t) * width * height));

    [self clearMaze];
    [self createWalls];

    pathLen      = 0;
    path [0].x   = startX;
    path [0].y   = startY;

    CELL (startX, startY) |= VISITED_SQUARE;
}



// Creates an empty maze with outer walls, space for a logo, and a start/endposition.
- (void)clearMaze
{
    int x, y, wall;


    // No doors for all cells
    memset (maze, 0, sizeof (int) * width * height);


    // Outer walls
    for (x = 0; x < width; x++)
    {
        CELL (x, 0)          |= WALL_BOTTOM;
        CELL (x, height - 1) |= WALL_TOP;
    }

    for (y = 0; y < height; y++)
    {
        CELL (0,         y) |= WALL_LEFT;
        CELL (width - 1, y) |= WALL_RIGHT;
    }


    // Start square
    switch ((wall = NRAND (4)))
    {
        case DIR_DOWN:   x = NRAND (width);   y = 0;               break;
        case DIR_RIGHT:  x = width - 1;       y = NRAND (height);  break;
        case DIR_UP:     x = NRAND (width);   y = height - 1;      break;
        case DIR_LEFT:   x = 0;               y = NRAND (height);  break;
    }

    CELL (x, y) &= ~(WALL_BOTTOM >> wall);
    CELL (x, y) |= (START_SQUARE | (DOOR_IN_BOTTOM >> wall));

    startX   = x;
    startY   = y;
    startDir = wall;


    // End square
    switch ((wall = (wall + 2) % 4))
    {
        case DIR_DOWN:   x = NRAND (width);   y = 0;               break;
        case DIR_RIGHT:  x = width - 1;       y = NRAND (height);  break;
        case DIR_UP:     x = NRAND (width);   y = height - 1;      break;
        case DIR_LEFT:   x = 0;               y = NRAND (height);  break;
    }

    CELL (x, y) &= ~(WALL_BOTTOM >> wall);
    CELL (x, y) |= (END_SQUARE | (DOOR_OUT_BOTTOM >> wall));

    endX   = x;
    endY   = y;
    endDir = wall;


    // Space for logo
    if (logo != nil && width > logoSize + 10 && height > logoSize + 10)
    {
        logoX = NRAND (width  - logoSize - 10) + 5;
        logoY = NRAND (height - logoSize - 10) + 5;

        for (x = 0; x < logoSize; x++)
            for (y = 0; y < logoSize; y++)
                CELL (logoX + x, logoY + y) |= DOOR_IN_ANY;
    }
}



// Randomly chooses a direction to leave the current cell.
- (int)chooseDirectionForX:(int)X Y:(int)Y
{
    int cand [3], count = 0;


    // Top wall
    if ((CELL (X, Y) & (DOOR_IN_BOTTOM | DOOR_OUT_BOTTOM | WALL_BOTTOM)) == 0)
    {
        if (CELL (X, Y - 1) & DOOR_IN_ANY)
        {
            CELL (X, Y)     |= WALL_BOTTOM;
            CELL (X, Y - 1) |= WALL_TOP;
        }
        else
            cand [count++] = DIR_DOWN;
	}


    // Right wall
    if ((CELL (X, Y) & (DOOR_IN_RIGHT | DOOR_OUT_RIGHT | WALL_RIGHT)) == 0)
    {
        if (CELL (X + 1, Y) & DOOR_IN_ANY)
        {
            CELL (X, Y)     |= WALL_RIGHT;
            CELL (X + 1, Y) |= WALL_LEFT;
        }
        else
            cand [count++] = DIR_RIGHT;
	}


    // Bottom wall
    if ((CELL (X, Y) & (DOOR_IN_TOP | DOOR_OUT_TOP | WALL_TOP)) == 0)
    {
        if (CELL (X, Y + 1) & DOOR_IN_ANY)
        {
            CELL (X, Y)     |= WALL_TOP;
            CELL (X, Y + 1) |= WALL_BOTTOM;
        }
        else
            cand [count++] = DIR_UP;
	}


    // Left wall
    if ((CELL (X, Y) & (DOOR_IN_LEFT | DOOR_OUT_LEFT | WALL_LEFT)) == 0)
    {
        if (CELL (X - 1, Y) & DOOR_IN_ANY)
        {
            CELL (X, Y)     |= WALL_LEFT;
            CELL (X - 1, Y) |= WALL_RIGHT;
        }
        else
            cand [count++] = DIR_LEFT;
	}

    return (count == 0) ? DIR_NONE : cand [NRAND (count)];
}



// Creates a random depth first search walk in the empty maze and marks walls. The created maze has at most one solution and is cycle-free.
- (void)createWalls
{
    int x = startX;
    int y = startY;


    for (pathLen = 0; ; pathLen ++)
    {
        int nextDirection;


        // Push current position
        path [pathLen].x = x;
        path [pathLen].y = y;


        // Choose a new walking direction
        while ((nextDirection = [self chooseDirectionForX:x Y:y]) == DIR_NONE)
        {
            // No direction found => backtrack
            if (--pathLen >= 0)
            {
                x = path [pathLen].x;
                y = path [pathLen].y;
         	}
            else
                return;
        }


        // Mark the outgoing door
        CELL (x, y) |= (DOOR_OUT_BOTTOM >> nextDirection);

        switch (nextDirection)
        {
            case DIR_DOWN:  y -= 1; break;
            case DIR_RIGHT: x += 1; break;
            case DIR_UP:    y += 1; break;
            case DIR_LEFT:  x -= 1; break;
        }


        // Mark the incoming door
        CELL (x, y) |= (DOOR_IN_BOTTOM >> ((nextDirection + 2) % 4));
    }
}

@end
