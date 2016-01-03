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

// SVGImportPath.as
// John Maloney, June 2012
//
// Generate an array of simplified, absolute path commands for an SVG shape or
// line element such as a circle, ellipse, line, paths, polygons, and polylines.
// A simplified path contains only M, L, C, and Q commands with absolute coordinates.
//
// Using a standard path format simplifies the rendering and editing code.

package svgutils;
	import flash.geom.Point;
	import flash.geom.Matrix;

class SVGImportPath {

	// -----------------------------
	// Generate path commands for circles, ellipses, lines, polylines, polygon, and rects.
	//------------------------------

	public function generatePathCmds(el:SVGElement):Void {
		// Generate a path command list for the given element, if applicable.
		switch (el.tag) {
		case 'circle': el.path = cmdsForCircleOrEllipse(el); break;
		case 'ellipse': el.path = cmdsForCircleOrEllipse(el); break;
		case 'line': el.path = cmdsForLine(el); break;
		case 'path': el.path = cmdsForPath(el); break;
		case 'polygon': el.path = cmdsForPolygon(el); break;
		case 'polyline': el.path = cmdsForPolyline(el); break;
		case 'rect': el.path = cmdsForRect(el); break;
		}
	}

	private function cmdsForCircleOrEllipse(el:SVGElement):SVGPath {
		// Approximate ellipse with four Cubic Beziers.
		var cx:Float = el.getAttribute('cx', 100);
		var cy:Float = el.getAttribute('cy', 100);
		var rx:Float, ry:Float;
		if ('circle' == el.tag) {
			rx = ry = el.getAttribute('r', 10);
		} else {
			rx = el.getAttribute('rx', 10);
			ry = el.getAttribute('ry', 5);
		}

		var path:SVGPath = new SVGPath(['M', cx, cy - ry],
			quarterCircle(true, cx, cy - ry, cx + rx, cy),
			quarterCircle(false, cx + rx, cy, cx, cy + ry),
			quarterCircle(true, cx, cy + ry, cx - rx, cy),
			quarterCircle(false, cx - rx, cy, cx, cy - ry),['Z']);

		path.splitCurve(1, 0.5);
		path.splitCurve(3, 0.5);
		path.splitCurve(5, 0.5);
		path.splitCurve(7, 0.5);
		return path;
	}

	private function quarterCircle(xFirst:Bool, srcX:Float, srcY:Float, dstX:Float, dstY:Float):Array<Dynamic> {
		// Approximate a quarter ellipse using a cubic Bezier curve, based on
		// "Approximating a Circle or an Ellipse Using Four Bezier Cubic Splines" by Don Lancaster.
		var k:Float = 0.551784; // magic constant
		var dx:Float = dstX - srcX;
		var dy:Float = dstY - srcY;
		return xFirst ?
			['C', srcX + (k * dx), srcY, dstX, dstY - (k * dy), dstX, dstY] :
			['C', srcX, srcY + (k * dy), dstX - (k * dx), dstY, dstX, dstY];
	}

	private function cmdsForLine(el:SVGElement):SVGPath {
		return new SVGPath(
			['M', el.getAttribute('x1', 0), el.getAttribute('y1', 0)],
			['L', el.getAttribute('x2', 0), el.getAttribute('y2', 0)]);
	}

	private function cmdsForPolygon(el:SVGElement):SVGPath {
		var result:SVGPath = cmdsForPolyline(el);
		if (result.length == 0) return new SVGPath();
		var firstCmd:Array<Dynamic> = result[0];
		result.push(['L', firstCmd[1], firstCmd[2]]); // close the polygon
		return result;
	}

	private function cmdsForPolyline(el:SVGElement):SVGPath {
		var result:SVGPath = new SVGPath();
		var points:Array<Dynamic> = el.extractNumericArgs(el.getAttribute('points', ''));
		if (points.length < 4) return new SVGPath();
		result.push(['M', points[0], points[1]]);
		var i:Int = 2; 
		while (i < (points.length - 1)) {
			result.push(['L', points[i], points[i + 1]]);
			i += 2;
		}
		return result;
	}

	private function cmdsForRect(el:SVGElement):SVGPath {
		var left:Float = el.getAttribute('x', 0);
		var top:Float = el.getAttribute('y', 0);
		var w:Float = el.getAttribute('width', 10);
		var h:Float = el.getAttribute('height', 10);
		return new SVGPath(
			['M', left, top],
			['L', left + w, top],
			['L', left + w, top + h],
			['L', left, top + h],
			['L', left, top],['Z']);
	}

	// -----------------------------
	// Parse an SVG path and generate an array of simplified, absolute path commands.
	//------------------------------

	private var firstMove:Bool;
	private var startX:Float;
	private var startY:Float;
	private var lastX:Float;
	private var lastY:Float;
	private var lastCX:Float;
	private var lastCY:Float;

	private function cmdsForPath(el:SVGElement):SVGPath {
		// Convert an SVG path to a Flash-friendly version that contains only absolute
		// move, line, cubic, and quadratic curve commands (M, L, C, Q). The output is
		// an array of command arrays of the form [<cmd> args...].
		var cmds:Array<Dynamic> = [];
		firstMove = true;
		startX = startY = 0;
		lastX = lastY = 0;
		lastCX = lastCY = 0;
		var svgPath:String = el.getAttribute('d');
		for (cmdString in svgPath.match(~/[A-DF-Za-df-z][^A-Za-df-z]*/g)) {
			var cmd:String = cmdString.charAt(0);
			var args:Array<Dynamic> = el.extractNumericArgs(cmdString.substr(1));
			var argCount:Int = pathCmdArgCount[cmd];
			if (argCount == 0) {
				cmds.push(simplePathCommands(cmd, args));
				continue;
			}
			if (('m' == cmd.toLowerCase()) && (args.length > 2)) {
				// Special case: If 'M' or 'm' has more than 2 arguments, the
				// extra arguments are for an implied 'L' or 'l' line command.
				cmds.push(simplePathCommands(cmd, args));
				args = args.slice(2);
				cmd = ('M' == cmd) ? 'L' : 'l';
			}
			if (args.length == argCount) { // common case: no splicing necessary
				cmds.push(simplePathCommands(cmd, args));
			}
			else { // sequence commands of the same kind (with command letter omitted on subsequent commands)
				var argsPos:Int = 0;
				while (args.length >= argsPos + argCount) {
					cmds.push(simplePathCommands(cmd, args.slice(argsPos, argsPos + argCount)));
					argsPos += argCount;
				}
			}
		}
		// Flatten array-of-arrays to just one big array
		var flattened:Array<Dynamic> = [];
		flattened = flattened.concat.apply(flattened, cmds);
		var result:SVGPath = new SVGPath();
		result.set(flattened);
		return result;
	}

	private static inline var pathCmdArgCount:Dynamic = {
		A: 7, a: 7,
		C: 6, c: 6,
		H: 1, h: 1,
		L: 2, l: 2,
		M: 2, m: 2,
		Q: 4, q: 4,
		S: 4, s: 4,
		T: 2, t: 2,
		V: 1, v: 1,
		Z: 0, z: 0
	}

	private function simplePathCommands(cmd:String, args:Array<Dynamic>):Array<Dynamic> {
		// Return an array of simple path commands for the given SVG command letter
		// and arguments, converting relative commands to absolute ones.
		// Each command in resulting array is an array consists of a letter from the
		// set {M, L, C, Q, Z} followed by zero to six numeric arguments.
		// In general, arc cannot be represented by a single bezier curve precisely.
		// All other commands are packed into arrays to have the same format.
		switch (cmd) {//return array of commands
		case 'A': return arcCmds(args, false);
		case 'a': return arcCmds(args, true);
		case 'C': return [cubicCurveCmd(args, false)];
		case 'c': return [cubicCurveCmd(args, true)];
		case 'H': return [hLineCmd(args[0])];
		case 'h': return [hLineCmd(lastX + args[0])];
		case 'L': return [lineCmd(absoluteArgs(args))];
		case 'l': return [lineCmd(relativeArgs(args))];
		case 'M': return [moveCmd(absoluteArgs(args))];
		case 'm': return [moveCmd(relativeArgs(args))];
		case 'Q': return [quadraticCurveCmd(args, false)];
		case 'q': return [quadraticCurveCmd(args, true)];
		case 'S': return [cubicCurveSmoothCmd(args, false)];
		case 's': return [cubicCurveSmoothCmd(args, true)];
		case 'T': return [quadraticCurveSmoothCmd(args, false)];
		case 't': return [quadraticCurveSmoothCmd(args, true)];
		case 'V': return [vLineCmd(args[0])];
		case 'v': return [vLineCmd(lastY + args[0])];
		case 'Z':
		case 'z': return [['Z']];
		}
		trace('Unknown path command: ' + cmd); // unknown path command; should not happen
		return [];
	}

	private function absoluteArgs(args:Array<Dynamic>):Array<Dynamic> {
		lastX = args[0];
		lastY = args[1];
		return args;
	}

	private function relativeArgs(args:Array<Dynamic>):Array<Dynamic> {
		lastX += args[0];
		lastY += args[1];
		return args;
	}

	private function arcCmds(args:Array<Dynamic>, isRelative:Bool):Array<Dynamic> {
		// Return array of bezier curves, approximating given arc.
		// Points :
		// A: arc begin; B: arc end; M: midpoint of AB; C: center of ellipse
		// TTemp: consequently maps points of ellipse to a unitary circle
		// TForward: circle to ellipse transform, all at once
		// See: http://www.w3.org/TR/SVG/paths/p.a#PathDataEllipticalArcCommands
		var a:Point = new Point(lastX, lastY);
		lastX = isRelative ? lastX + args[5] : args[5];
		lastY = isRelative ? lastY + args[6] : args[6];
		var b:Point = new Point(lastX, lastY);
		var ab_length:Float = Point.distance(a, b);
		if (ab_length == 0) {
			return [];
		}
		var rx:Float = (args[0] * args[1] == 0) ? (ab_length / 2) : Math.abs(args[0]);
		var ry:Float = (args[0] * args[1] == 0) ? (ab_length / 2) : Math.abs(args[1]);
		var largeArcFlag:Bool = (args[3] == 1);
		var sweepFlag:Bool = (args[4] == 1);
		var convexityFlag:Float = (largeArcFlag == sweepFlag) ? 1 : -1;
		var TTemp:Matrix = new Matrix();
		TTemp.rotate(-args[2] / Math.PI * 180);
		TTemp.scale(1/rx, 1/ry);
		a = TTemp.transformPoint(a);
		b = TTemp.transformPoint(b);
		ab_length = Point.distance(a, b);
		var extraScale:Float = (ab_length > 2) ? ab_length / 2 : 1;
		TTemp = new Matrix();
		TTemp.scale(1 / extraScale, 1 / extraScale);
		a = TTemp.transformPoint(a);
		b = TTemp.transformPoint(b);
		ab_length = Point.distance(a, b);
		var ab:Point = new Point(b.x - a.x, b.y - a.y);
		var m:Point = new Point((a.x + b.x) / 2, (a.y + b.y) / 2);
		var mc_length:Float = Math.sqrt(Math.max(0, 1 - ab_length * ab_length / 4));
		var mc:Point = new Point(convexityFlag * ab.y / ab_length * mc_length, -convexityFlag * ab.x / ab_length * mc_length);
		var c:Point = new Point(m.x + mc.x, m.y + mc.y);
		TTemp = new Matrix();
		TTemp.translate(-c.x, -c.y);
		a = TTemp.transformPoint(a);
		b = TTemp.transformPoint(b);
		var aPhi:Float = Math.atan2(a.y, a.x);
		var bPhi:Float = Math.atan2(b.y, b.x);
		var phi:Float = bPhi - aPhi;
		if (sweepFlag && phi < 0) {
			phi += 2 * Math.PI;
		}
		if (!sweepFlag && phi > 0) {
			phi -= 2 * Math.PI;
		}
		var TForward:Matrix = new Matrix();
		TForward.translate(c.x, c.y);
		TForward.scale(rx * extraScale, ry * extraScale);
		TForward.rotate(args[2] / Math.PI * 180);
		var PHI_MAX:Float = Math.PI / 2 * 1.001;//Produce no more than 2 curves for semicircle
		var steps:Int = Math.ceil(Math.abs(phi) / PHI_MAX);
		var k:Float = 4 / 3 * (1 - Math.cos(phi / 2 / steps)) / Math.sin(phi / 2 / steps);
		var result:Array<Dynamic> = new Array<Dynamic>();
		for (i= 0...steps) {
			var alpha:Float = aPhi + phi * (i / steps);
			var beta:Float = aPhi + phi * ((i+1) / steps);
			var control1:Point = TForward.transformPoint(new Point(Math.cos(alpha) - k * Math.sin(alpha), Math.sin(alpha) + k * Math.cos(alpha)));
			var control2:Point = TForward.transformPoint(new Point(Math.cos(beta) + k * Math.sin(beta), Math.sin(beta) - k * Math.cos(beta)));
			var finish:Point = TForward.transformPoint(new Point(Math.cos(beta), Math.sin(beta)));
			result.push(['C', control1.x, control1.y, control2.x, control2.y, finish.x, finish.y]);
		}
		return result;
	}

	private function closePath():Array<Dynamic> {
		lastX = startX;
		lastY = startY;
		firstMove = true;
		return ['L', lastX, lastY];
	}

	private function hLineCmd(endX:Float):Array<Dynamic> {
		lastX = endX;
		return ['L', lastX, lastY];
	}

	private function lineCmd(args:Array<Dynamic>):Array<Dynamic> {
		return ['L', lastX, lastY];
	}

	private function moveCmd(args:Array<Dynamic>):Array<Dynamic> {
		if (firstMove) {
			startX = lastX;
			startY = lastY;
			lastCX = lastX;
			lastCY = lastY;
			firstMove = false;
		}
		return ['M', lastX, lastY];
	}

	private function vLineCmd(endY:Float):Array<Dynamic> {
		lastY = endY;
		return ['L', lastX, lastY];
	}

	private function cubicCurveCmd(args:Array<Dynamic>, isRelative:Bool):Array<Dynamic> {
		// 'C' or 'c' command. Args: cx1 cy1 cx2 cy2 x y
		var c1x:Float = isRelative ? lastX + args[0] : args[0];
		var c1y:Float = isRelative ? lastY + args[1] : args[1];
		lastCX = isRelative ? lastX + args[2] : args[2];
		lastCY = isRelative ? lastY + args[3] : args[3];
		lastX = isRelative ? lastX + args[4] : args[4];
		lastY = isRelative ? lastY + args[5] : args[5];
		return ['C', c1x, c1y, lastCX, lastCY, lastX, lastY];
	}

	private function cubicCurveSmoothCmd(args:Array<Dynamic>, isRelative:Bool):Array<Dynamic> {
		// 'S' or 's' command. Args: cx2 cy2 x y
		var c1x:Float = lastX + (lastX - lastCX);
		var c1y:Float = lastY + (lastY - lastCY);
		lastCX = isRelative ? lastX + args[0] : args[0];
		lastCY = isRelative ? lastY + args[1] : args[1];
		lastX = isRelative ? lastX + args[2] : args[2];
		lastY = isRelative ? lastY + args[3] : args[3];
		return ['C', c1x, c1y, lastCX, lastCY, lastX, lastY];
	}

	private function quadraticCurveCmd(args:Array<Dynamic>, isRelative:Bool):Array<Dynamic> {
		// 'Q' or 'q' command. Args: cx cy x y
		var p0x:Float = lastX;
		var p0y:Float = lastY;
		lastCX = isRelative ? lastX + args[0] : args[0];
		lastCY = isRelative ? lastY + args[1] : args[1];
		lastX = isRelative ? lastX + args[2] : args[2];
		lastY = isRelative ? lastY + args[3] : args[3];
		var c1x:Float = p0x + (lastCX - p0x) * 2/3;
		var c1y:Float = p0y + (lastCY - p0y) * 2/3;
		var c2x:Float = lastX + (lastCX - lastX) * 2/3;
		var c2y:Float = lastY + (lastCY - lastY) * 2/3;

		return ['C', c1x, c1y, c2x, c2y, lastX, lastY];
	}

	private function quadraticCurveSmoothCmd(args:Array<Dynamic>, isRelative:Bool):Array<Dynamic> {
		// 'T' or 't' command. Args: x y
		// Control point is the reflection of the last control point through the last endpoint.
		var p0x:Float = lastX;
		var p0y:Float = lastY;
		lastCX = lastX + (lastX - lastCX);
		lastCY = lastY + (lastY - lastCY);
		lastX = isRelative ? lastX + args[0] : args[0];
		lastY = isRelative ? lastY + args[1] : args[1];
		var c1x:Float = p0x + (lastCX - p0x) * 2/3;
		var c1y:Float = p0y + (lastCY - p0y) * 2/3;
		var c2x:Float = lastX + (lastCX - lastX) * 2/3;
		var c2y:Float = lastY + (lastCY - lastY) * 2/3;

		return ['C', c1x, c1y, c2x, c2y, lastX, lastY];
	}

}
