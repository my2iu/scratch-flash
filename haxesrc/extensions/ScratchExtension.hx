/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// ScratchExtension.as
// John Maloney, March 2013
//
// Contains the name, port number, and block specs for an extension, as well as its runtime state.
// This file also defines the extensions built into Scratch (e.g. WeDo, PicoBoard).
//
// Extension block types:
//	' ' - command block
//  'w' - command block that waits
//	'r' - reporter block (returns a number or string)
//	'R' - http reporter block that waits for the callback (returns a number or string)
//	'b' - boolean reporter block
//	'-' - (not actually a block) add some blank space between blocks
//
// Possible argument slots:
//	'%n' - number argument slot
//	'%s' - string argument slot
//	'%b' - boolean argument slot

package extensions;


import flash.utils.Dictionary;

class ScratchExtension
{
    
    public var name : String = "";
    public var host : String = "127.0.0.1";  // most extensions run on the local host  
    public var port : Int = 0;
    public var id : Int = 0;
    public var blockSpecs : Array<Dynamic> = [];
    public var isInternal : Bool;
    public var useScratchPrimitives : Bool;  // true for extensions built into Scratch (WeDo, PicoBoard) that have custom primitives  
    public var showBlocks : Bool;
    public var menus : Dynamic = { };
    public var thumbnailMD5 : String = "";  // md5 has for extension image shown in extension library  
    public var url : String = "";  // URL for extension documentation page (with helper app download link, if appropriate)  
    public var javascriptURL : String = "";  // URL to load a JavaScript extension  
    public var tags : Array<Dynamic> = [];  // tags for the extension library filter  
    
    // Runtime state
    public var stateVars : Dynamic = { };
    public var lastPollResponseTime : Int;
    public var problem : String = "";
    public var success : String = "Okay";
    public var nextID : Int;
    public var busy : Array<Dynamic> = [];
    public var waiting : Dictionary = new Dictionary(true);
    
    public function new(name : String, port : Int)
    {
        this.name = name;
        this.port = port;
    }
}

