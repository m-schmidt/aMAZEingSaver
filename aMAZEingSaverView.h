// aMAZEingSaverView.h
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


#import <ScreenSaver/ScreenSaver.h>


typedef struct
{
  int x;
  int y;
} path_t;


@interface aMAZEingSaverView : ScreenSaverView
{
  BOOL isPreview;
  int delayCounter;

  int cellSize;           // size of a cell in pixels
  int baseX, baseY;       // origin for drawing

  int width, height;      // size of maze in cells
  int *maze;              // the maze cells

  int startX, startY;     // entry cell of maze
  int startDir;

  int endX, endY;         // exit cell of maze
  int endDir;

  int logoSize;           // size of logo in cells
  int logoX, logoY;       // start cell of logo

  path_t *path;           // a working stack
  int pathLen;
}

@end
