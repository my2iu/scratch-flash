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

package svgeditor.tools;

import svgeditor.tools.PathControlPoint;
import svgeditor.tools.PathEditTool;

import flash.display.Graphics;
import flash.display.Sprite;
import flash.display.Stage;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.geom.Point;

class PathAnchorPoint extends Sprite
{
    public var index(get, set) : Int;
    public var endPoint(get, set) : Bool;

    // Standard anchor point
    private static inline var h_fill : Int = 0xCCCCCC;  // highlight version  
    private static inline var fill : Int = 0xFFFFFF;
    
    // End point anchor
    private static inline var ep_h_fill : Int = 0xCCEECC;  // highlight version  
    private static inline var ep_fill : Int = 0xDDFFDD;
    
    private static inline var stroke : Int = 0x28A5DA;
    private static inline var h_opacity : Float = 1.0;  // highlight version  
    private static inline var opacity : Float = 0.6;
    private var pathEditTool : PathEditTool;
    private var _index : Int;
    private var controlPoints : Array<Dynamic>;
    private var isEndPoint : Bool;
    public function new(editTool : PathEditTool, idx : Int, endPoint : Bool)
    {
        super();
        pathEditTool = editTool;
        _index = idx;
        isEndPoint = endPoint;
        
        render(graphics, false, isEndPoint);
        makeInteractive();
        
        // TODO: enable this when the user is altering control points
        if (false) {
            var pcp : PathControlPoint = editTool.getControlPoint(idx, true);
            if (pcp != null) {
                controlPoints = [];
                controlPoints.push(pcp);
                controlPoints.push(editTool.getControlPoint(idx, false));
                addEventListener(Event.REMOVED, removedFromStage, false, 0, true);
            }
        }
    }
    
    private function set_index(idx : Int) : Int{
        _index = idx;
        if (controlPoints != null) {
            controlPoints[0].index = idx;
            controlPoints[1].index = idx;
        }
        return idx;
    }
    
    private function get_index() : Int{
        return _index;
    }
    
    private function set_endPoint(ep : Bool) : Bool{
        isEndPoint = ep;
        render(graphics, false, isEndPoint);
        return ep;
    }
    
    private function get_endPoint() : Bool{
        return isEndPoint;
    }
    
    private function removedFromStage(e : Event) : Void{
        if (e.target != this)             return;
        
        removeEventListener(Event.REMOVED, removedFromStage);
        pathEditTool.removeChild(controlPoints.pop());
        pathEditTool.removeChild(controlPoints.pop());
    }
    
    public static function render(g : Graphics, highlight : Bool = false, endPoint : Bool = false) : Void{
        g.clear();
        g.lineStyle(1, stroke, ((highlight) ? h_opacity : opacity));
        var f : Int;
        if (endPoint) 
            f = (highlight) ? ep_h_fill : ep_fill
        else 
        f = (highlight) ? h_fill : fill;
        g.beginFill(f, ((highlight) ? h_opacity : opacity));
        g.drawCircle(0, 0, 5);
        g.endFill();
    }
    
    private function makeInteractive() : Void{
        addEventListener(MouseEvent.MOUSE_DOWN, eventHandler, false, 0, true);
        addEventListener(MouseEvent.MOUSE_OVER, toggleHighlight, false, 0, true);
        addEventListener(MouseEvent.MOUSE_OUT, toggleHighlight, false, 0, true);
    }
    
    private var wasMoved : Bool = false;
    private var canDelete : Bool = false;
    private function eventHandler(event : MouseEvent) : Void{
        var p : Point;
        var _stage : Stage = Scratch.app.stage;
        var _sw6_ = (event.type);        

        switch (_sw6_)
        {
            case MouseEvent.MOUSE_DOWN:
                _stage.addEventListener(MouseEvent.MOUSE_MOVE, arguments.callee);
                _stage.addEventListener(MouseEvent.MOUSE_UP, arguments.callee);
                wasMoved = false;
                canDelete = !Math.isNaN(event.localX);
            case MouseEvent.MOUSE_MOVE:
                p = new Point(_stage.mouseX, _stage.mouseY);
                pathEditTool.movePoint(index, p);
                p = pathEditTool.globalToLocal(p);
                x = p.x;
                y = p.y;
                wasMoved = true;
            case MouseEvent.MOUSE_UP:
                _stage.removeEventListener(MouseEvent.MOUSE_MOVE, arguments.callee);
                _stage.removeEventListener(MouseEvent.MOUSE_UP, arguments.callee);
                
                // Save the path
                p = new Point(x, y);
                p = pathEditTool.localToGlobal(p);
                pathEditTool.movePoint(index, p, true);
                
                if (!wasMoved && canDelete)                     pathEditTool.removePoint(index, event);
        }
    }
    
    private function toggleHighlight(e : MouseEvent) : Void{
        render(graphics, e.type == MouseEvent.MOUSE_OVER, isEndPoint);
    }
}

