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

// ScratchCostume.as
// John Maloney, April 2010
// John Maloney, January 2011 (major restructure)
//
// A Scratch costume (or scene) is a named image with a rotation center.
// The bitmap field contains the composite costume image.
//
// Internally, a costume consists of a base image and an optional text layer.
// If a costume has a text layer, the text image is stored as a separate
// bitmap and composited with the base image to create the costume bitmap.
// Storing the text layer separately allows the text to be changed independent
// of the base image. Saving the text image means that costumes with text
// do not depend on the fonts available on the viewer's computer. (However,
// editing the text *does* depend on the user's fonts.)
//
// The source data (GIF, PNG, JPEG, or SVG format) for each layer is retained so
// that it does not need to be recomputed when saving the project. This also
// avoids the possible image degradation that might occur when repeatedly
// converting to/from JPEG format.

package scratch;
	import openfl.display.*;
	import openfl.geom.*;
	import openfl.text.TextField;
	import openfl.utils.*;
	import openfl.display.BitmapData;
	import svgutils.*;
	import util.*;
	import openfl.utils.ByteArray;
	//import by.blooddy.crypto.MD5;
	//import by.blooddy.crypto.image.PNG24Encoder;
	//import by.blooddy.crypto.image.PNGFilter;

class ScratchCostume {

	public var costumeName:String;
	public var bitmap:BitmapData; // composite bitmap (base layer + text layer)
	public var bitmapResolution:Int = 1; // used for double or higher resolution costumes
	public var rotationCenterX:Int;
	public var rotationCenterY:Int;

	public var baseLayerBitmap:BitmapData;
	public var baseLayerID:Int = -1;
	public var baseLayerMD5:String;
	private var __baseLayerData:ByteArray;

	public static inline var WasEdited:Int = -10; // special baseLayerID used to indicate costumes that have been edited

//	public var svgRoot:SVGElement; // non-null for an SVG costume
	public var svgLoading:Bool; // true while loading bitmaps embedded in an SVG
	private var svgSprite:Sprite;
	private var svgWidth:Float;
	private var svgHeight:Float;

	public var oldComposite:BitmapData; // composite bitmap from old Scratch file (used only during loading)

	public var textLayerBitmap:BitmapData;
	public var textLayerID:Int = -1;
	public var textLayerMD5:String;
	private var __textLayerData:ByteArray;

	public var text:String;
	public var textRect:Rectangle;
	public var textColor:Int;
	public var fontName:String;
	public var fontSize:Int;

	// Undo support; not saved
	public var undoList:Array<Dynamic> = [];
	public var undoListIndex:Int;

	private function new(name:String)
	{
		costumeName = name;
	}
	
	public static function fromSVG(name:String, data:ByteArray, centerX:Int = 99999, centerY:Int = 99999, bmRes:Int = 1) : ScratchCostume {
		var c = new ScratchCostume(name);
		c.rotationCenterX = centerX;
		c.rotationCenterY = centerY;
		c.setSVGData(data, (centerX == 99999));
		c.prepareToSave();
		return c;
	}
	
	public static function fromBitmapData(name:String, data:BitmapData, centerX:Int = 99999, centerY:Int = 99999, bmRes:Int = 1) : ScratchCostume {
		var c = new ScratchCostume(name);
		c.rotationCenterX = centerX;
		c.rotationCenterY = centerY;
		c.bitmap = c.baseLayerBitmap = data;
		c.bitmapResolution = bmRes;
		if (centerX == 99999) c.rotationCenterX = Std.int(c.bitmap.rect.width / 2);
		if (centerY == 99999) c.rotationCenterY = Std.int(c.bitmap.rect.height / 2);
		c.prepareToSave();
		return c;
	}
	
	public static function newEmptyCostume(name:String) : ScratchCostume {
		var c = new ScratchCostume(name);
		c.rotationCenterX = c.rotationCenterY = 0;
		return c;
	}

	public var baseLayerData (get, set) : ByteArray;
	public function get_baseLayerData():ByteArray {
		return __baseLayerData;
	}

	public function set_baseLayerData(data:ByteArray):ByteArray {
		__baseLayerData = data;
		baseLayerMD5 = null;
		return data;
	}

	public var textLayerData (get, set) : ByteArray;
	public function get_textLayerData():ByteArray {
		return __textLayerData;
	}

	public function set_textLayerData(data:ByteArray):ByteArray {
		__textLayerData = data;
		textLayerMD5 = null;
		return data;
	}

	public static function scaleForScratch(bm:BitmapData):BitmapData {
		if ((bm.width <= 480) && (bm.height <= 360)) return bm;
		var scale:Float = Math.min(480 / bm.width, 360 / bm.height);
		var result:BitmapData = new BitmapData(Std.int(scale * bm.width), Std.int(scale * bm.height), true, 0);
		var m:Matrix = new Matrix();
		m.scale(scale, scale);
		result.draw(bm, m);
		return result;
	}

	public static function isSVGData(data:ByteArray):Bool {
		if (data == null || (data.length < 10)) return false;
		var oldPosition:Int = data.position;
		data.position = 0;
		var s:String = data.readUTFBytes(10);
		data.position = oldPosition;
		return (s.indexOf('<?xml') >= 0) || (s.indexOf('<svg') >= 0);
	}

	public static function emptySVG():ByteArray {
		var data:ByteArray = new ByteArray();
		data.writeUTFBytes(
			'<svg width="0" height="0"\n' +
			'  xmlns="http://www.w3.org/2000/svg" version="1.1"\n' +
			'  xmlns:xlink="http://www.w3.org/1999/xlink">\n' +
			'</svg>\n');
		return data;
	}

	public static function emptyBackdropSVG():ByteArray {
		var data:ByteArray = new ByteArray();
		data.writeUTFBytes(
			'<svg width="480" height="360"\n' +
			'  xmlns="http://www.w3.org/2000/svg" version="1.1"\n' +
			'  xmlns:xlink="http://www.w3.org/1999/xlink">\n' +
			'	<rect x="0" y="0" width="480" height="360" fill="#FFF" scratch-type="backdrop-fill"> </rect>\n' +
			'</svg>\n');
		return data;
	}

	public static function emptyBitmapCostume(costumeName:String, forBackdrop:Bool):ScratchCostume {
		var bm:BitmapData = forBackdrop ?
			new BitmapData(480, 360, true, 0xFFFFFFFF) :
			new BitmapData(1, 1, true, 0);
		var result:ScratchCostume = ScratchCostume.fromBitmapData(costumeName, bm);
		return result;
	}

	public function setBitmapData(bm:BitmapData, centerX:Int, centerY:Int):Void {
		clearOldCostume();
		bitmap = baseLayerBitmap = bm;
		baseLayerID = WasEdited;
		baseLayerMD5 = null;
		bitmapResolution = 2;
		rotationCenterX = centerX;
		rotationCenterY = centerY;
		if (Scratch.app != null && Scratch.app.viewedObj() != null && (Scratch.app.viewedObj().currentCostume() == this)) {
			Scratch.app.viewedObj().updateCostume();
			Scratch.app.refreshImageTab(true);
		}
	}

	public function setSVGData(data:ByteArray, computeCenter:Bool, fromEditor:Bool = true):Void {
		// Initialize an SVG costume.
		/*
		function refreshAfterImagesLoaded():Void {
			svgSprite = new SVGDisplayRender().renderAsSprite(svgRoot, false, true);
			if (Scratch.app && Scratch.app.viewedObj() && (Scratch.app.viewedObj().currentCostume() == thisC)) {
				Scratch.app.viewedObj().updateCostume();
				Scratch.app.refreshImageTab(fromEditor);
			}
			svgLoading = false;
		}*/
		var thisC:ScratchCostume = this; // record "this" for use in callback
		clearOldCostume();
		baseLayerData = data;
		baseLayerID = WasEdited;
		/*
		var importer:SVGImporter = new SVGImporter(XML(data));
		setSVGRoot(importer.root, computeCenter);
		svgLoading = true;
		importer.loadAllImages(refreshAfterImagesLoaded);
		*/
	}

	/*
	public function setSVGRoot(svg:SVGElement, computeCenter:Bool):Void {
		svgRoot = svg;
		svgSprite = new SVGDisplayRender().renderAsSprite(svgRoot, false, true);
		var r:Rectangle;
		var viewBox:Array = svg.getAttribute('viewBox', '').split(' ');
		if (viewBox.length == 4) r = new Rectangle(viewBox[0], viewBox[1], viewBox[2], viewBox[3]);
		if (!r) {
			var w:Float = svg.getAttribute('width', -1);
			var h:Float = svg.getAttribute('height', -1);
			if ((w >= 0) && (h >= 0)) r = new Rectangle(0, 0, w, h);
		}
		if (!r) r = svgSprite.getBounds(svgSprite);
		svgWidth = r.x + r.width;
		svgHeight = r.y + r.height;
		if (computeCenter) {
			rotationCenterX = r.x + (r.width / 2);
			rotationCenterY = r.y + (r.height / 2);
		}
	}
	*/

	private function clearOldCostume():Void {
		bitmap = null;
		baseLayerBitmap = null;
		bitmapResolution = 1;
		baseLayerID = -1;
		baseLayerData = null;
		//svgRoot = null;
		svgSprite = null;
		svgWidth = svgHeight = 0;
		oldComposite = null;
		textLayerBitmap = null;
		textLayerID = -1;
		textLayerMD5 = null;
		textLayerData = null;
		text = null;
		textRect = null;
	}

	public function isBitmap():Bool { return baseLayerBitmap != null; }

	public function displayObj():DisplayObject {
		/*
		if (svgRoot) {
			if (!svgSprite) svgSprite = new SVGDisplayRender().renderAsSprite(svgRoot, false, true);
			return svgSprite;
		}
		*/

		var bitmapObj:Bitmap = new Bitmap(bitmap);
		bitmapObj.scaleX = bitmapObj.scaleY = 1 / bitmapResolution;
		return bitmapObj;
	}

	private static var shapeDict:Map<String,Shape> = new Map<String,Shape>();
	public function getShape():Shape {
		if (baseLayerMD5 == null) prepareToSave();
		var id:String = baseLayerMD5;
		if(id != null && textLayerMD5 != null) id += textLayerMD5;
		else if(textLayerMD5 != null) id = textLayerMD5;

		var s:Shape = shapeDict[id];
		if(s == null) {
			s = new Shape();
			var pts:Array<Point> = RasterHull();
			s.graphics.clear();

			if(pts.length != 0) {
				s.graphics.lineStyle(1);
				s.graphics.moveTo(pts[Std.int(pts.length-1)].x, pts[Std.int(pts.length-1)].y);
				for (pt in pts)
					s.graphics.lineTo(pt.x, pt.y);
			}

			if(id != null)
				shapeDict[id] = s;
		}

		return s;
	}

	/* > 0 ; counter clockwise order */
	/* =0 ; C is on the line AB; */
	/* <0 ; clockwise order; */
	private function CCW(A:Point, B:Point, C:Point):Float {
		return ((B.x-A.x)*(C.y-A.y)-(B.y-A.y)*(C.x-A.x));
	}

	/* make a convex hull of boundary of foreground object in the binary
	 image */
	/* in some case L[0]=R[0], or L[ll]=R[rr] if first line or last line of
	 object is composed of
	 ** a single point
	 */
	private function RasterHull():Array<Point>
	{
		var dispObj:DisplayObject = displayObj();
		var r:Rectangle = dispObj.getBounds(dispObj);
//trace('flash bounds: '+r);
		if(r.width < 1 || r.height < 1)
			return [new Point()];

		r.width += Math.floor(r.left) - r.left;
		r.left = Math.floor(r.left);
		r.height += Math.floor(r.top) - r.top;
		r.top = Math.floor(r.top);
		var image:BitmapData = new BitmapData(Std.int(Math.max(1, Math.ceil(r.width)+1)), Std.int(Math.max(1, Math.ceil(r.height)+1)), true, 0);
//trace('bitmap rect: '+image.rect);

		var m:Matrix = new Matrix();
		m.translate(-r.left, -r.top);
		m.scale(image.width / r.width, image.height / r.height);
		image.draw(dispObj, m);

		var L:Array<Point> = Compat.newArray(image.height, null); // new Array<Point>(image.height); //stack of left-side hull;
		var R:Array<Point> = Compat.newArray(image.height, null); // new Array<Point>(image.height); //stack of right side hull;
		//var H:Vector.<Point> = new Vector.<Point>();
		var H:Array<Point> = [];
		var rr:Int=-1, ll:Int=-1;
		var Q:Point = new Point();
		var w:Int = image.width;
		var h:Int = image.height;
//		var minX:Int = image.width;
//		var minY:Int = image.height;
//		var maxX:Int = 0;
//		var maxY:Int = 0;
		var c:UInt;
		for (y in 0...h) {
			var x: Int = 0;
			while (x < w) {
				c = (image.getPixel32(x, y) >> 24) & 0xff;
				if (c > 0) break;
				x++;
			}
			if(x==w) continue;

			Q.x = x + r.left; Q.y = y + r.top;
			while(ll>0){
				if(CCW(L[ll-1],L[ll],Q)<0)
					break;
				else
					--ll;
			}

//			minX = Math.min(minX, Q.x);
//			minY = Math.min(minY, Q.y);
//			maxX = Math.max(maxX, Q.x);
//			maxY = Math.max(maxY, Q.y);
			L[++ll] = Q.clone();
			x = w - 1;
			while (x >= 0){//x=-1 never occurs;
				c = (image.getPixel32(x, y) >> 24) & 0xff;
				if (c > 0) break;
				x--;
			}

			Q.x = x + r.left;
//			minX = Math.min(minX, Q.x);
//			maxX = Math.max(maxX, Q.x);
			while(rr>0) {
				if(CCW(R[rr-1], R[rr], Q)>0)
					break;
				else
					--rr;
			}
			R[++rr] = Q.clone();
		}

		/* collect final results*/
		var i:Int = 0;
		while (i < ll+1) {
			H[i] = L[i]; //left part;
			i++;
		}

		var j:Int = rr;
		while (j >= 0) {
			H[i] = R[j]; //right part;
			i++;
			j--;
		}

		//R.length = L.length = 0;  // Not sure why this is necessary
		image.dispose();

//trace('found bounds: '+new Rectangle(minX, minY, maxX - minX, maxY - minY));
		return H;
	}

	public function width():Float { return /*svgRoot!=null ? svgWidth : */(bitmap != null ? bitmap.width / bitmapResolution : 0); }
	public function height():Float { return /*svgRoot!=null ? svgHeight : */(bitmap != null? bitmap.height / bitmapResolution : 0); }

	public function duplicate():ScratchCostume {
		// Return a copy of this costume.

		if (oldComposite != null) computeTextLayer();

		var dup:ScratchCostume = ScratchCostume.newEmptyCostume(costumeName);
		dup.bitmap = bitmap;
		dup.bitmapResolution = bitmapResolution;
		dup.rotationCenterX = rotationCenterX;
		dup.rotationCenterY = rotationCenterY;

		dup.baseLayerBitmap = baseLayerBitmap;
		dup.baseLayerData = baseLayerData;
		dup.baseLayerMD5 = baseLayerMD5;

		//dup.svgRoot = svgRoot;
		dup.svgWidth = svgWidth;
		dup.svgHeight = svgHeight;

		dup.textLayerBitmap = textLayerBitmap;
		dup.textLayerData = textLayerData;
		dup.textLayerMD5 = textLayerMD5;

		dup.text = text;
		dup.textRect = textRect;
		dup.textColor = textColor;
		dup.fontName = fontName;
		dup.fontSize = fontSize;

		//if(svgRoot && svgSprite) dup.setSVGSprite(cloneSprite(svgSprite));

		return dup;
	}

	private function cloneSprite(spr:Sprite):Sprite {
		var clone:Sprite = new Sprite();
		clone.graphics.copyFrom(spr.graphics);
		clone.x = spr.x;
		clone.y = spr.y;
		clone.scaleX = spr.scaleX;
		clone.scaleY = spr.scaleY;
		clone.rotation = spr.rotation;

		for(i in 0...spr.numChildren) {
			var dispObj:DisplayObject = spr.getChildAt(i);
			if(Std.is(dispObj, Sprite))
				clone.addChild(cloneSprite(cast(dispObj, Sprite)));
			else if(Std.is(dispObj, Shape)) {
				var shape:Shape = new Shape();
				shape.graphics.copyFrom((cast(dispObj, Shape)).graphics);
				shape.transform = dispObj.transform;
				clone.addChild(shape);
			}
			else if(Std.is(dispObj, Bitmap)) {
				var bm:Bitmap = new Bitmap((cast(dispObj, Bitmap)).bitmapData);
				bm.x = dispObj.x;
				bm.y = dispObj.y;
				bm.scaleX = dispObj.scaleX;
				bm.scaleY = dispObj.scaleY;
				bm.rotation = dispObj.rotation;
				bm.alpha = dispObj.alpha;
				clone.addChild(bm);
			}
			else if(Std.is(dispObj, TextField)) {
				var tf:TextField = new TextField();
				tf.selectable = false;
				tf.mouseEnabled = false;
				tf.tabEnabled = false;
				tf.textColor = (cast(dispObj, TextField)).textColor;
				tf.defaultTextFormat = (cast(dispObj, TextField)).defaultTextFormat;
				tf.embedFonts = (cast(dispObj, TextField)).embedFonts;
				tf.antiAliasType = (cast(dispObj, TextField)).antiAliasType;
				tf.text = (cast(dispObj, TextField)).text;
				tf.alpha = dispObj.alpha;
				tf.width = tf.textWidth + 6;
				tf.height = tf.textHeight + 4;

				tf.x = dispObj.x;
				tf.y = dispObj.y;
				tf.scaleX = dispObj.scaleX;
				tf.scaleY = dispObj.scaleY;
				tf.rotation = dispObj.rotation;
				clone.addChild(tf);
			}
		}

		return clone;
	}

	public function setSVGSprite(spr:Sprite):Void {
		svgSprite = spr;
	}

	public function thumbnail(w:Int, h:Int, forStage:Bool):BitmapData {
		var dispObj:DisplayObject = displayObj();
		var r:Rectangle = forStage ?
			new Rectangle(0, 0, 480 * bitmapResolution, 360 * bitmapResolution) :
			dispObj.getBounds(dispObj);
		var centerX:Float = r.x + (r.width / 2);
		var centerY:Float = r.y + (r.height / 2);
		var bm:BitmapData = new BitmapData(w, h, true, 0x00FFFFFF); // transparent fill color
		var scale:Float = Math.min(w / r.width, h / r.height);
		if (bitmap != null) scale = Math.min(1, scale);
		var m:Matrix = new Matrix();
		if (scale < 1 || bitmap == null) m.scale(scale, scale); // don't scale up bitmaps
		m.translate((w / 2) - (scale * centerX), (h / 2) - (scale * centerY));
		bm.draw(dispObj, m);
		return bm;
	}

	public function bitmapForEditor(forStage:Bool):BitmapData {
		// Return a double-resolution bitmap for use in the bitmap editor.
		var dispObj:DisplayObject = displayObj();
		var dispR:Rectangle = dispObj.getBounds(dispObj);
		var w:Int = Math.ceil(Math.max(1, dispR.width));
		var h:Int = Math.ceil(Math.max(1, dispR.height));
		if (forStage) { w = 480 * bitmapResolution; h = 360 * bitmapResolution; }

		var scale:Float = 2 / bitmapResolution;
		var bgColor:Int = forStage ? 0xFFFFFFFF : 0;
		var bm:BitmapData = new BitmapData(Std.int(scale * w), Std.int(scale * h), true, bgColor);
		var m:Matrix = new Matrix();
		if (!forStage) m.translate(-dispR.x, -dispR.y);
		m.scale(scale, scale);

		/*
		if (SCRATCH::allow3d) {
			bm.drawWithQuality(dispObj, m, null, null, null, false, StageQuality.LOW);
		}
		else {
		*/
			Scratch.app.ignoreResize = true;
			var oldQuality:StageQuality = Scratch.app.stage.quality;
			Scratch.app.stage.quality = StageQuality.LOW;
			bm.draw(dispObj, m);
			Scratch.app.stage.quality = oldQuality;
			Scratch.app.ignoreResize = false;
		/*	
		}
		*/

		return bm;
	}

	public function toString():String {
		var result:String = 'ScratchCostume(' + costumeName + ' ';
		result += rotationCenterX + ',' + rotationCenterY;
		result += /*svgRoot ? ' svg)' :*/ ' bitmap)';
		return result;
	}

	public function writeJSON(json:util.JSON):Void {
		json.writeKeyValue('costumeName', costumeName);
		json.writeKeyValue('baseLayerID', baseLayerID);
		json.writeKeyValue('baseLayerMD5', baseLayerMD5);
		json.writeKeyValue('bitmapResolution', bitmapResolution);
		json.writeKeyValue('rotationCenterX', rotationCenterX);
		json.writeKeyValue('rotationCenterY', rotationCenterY);
		if (text != null) {
			json.writeKeyValue('text', text);
			json.writeKeyValue('textRect', [textRect.x, textRect.y, textRect.width, textRect.height]);
			json.writeKeyValue('textColor', textColor);
			json.writeKeyValue('fontName', fontName);
			json.writeKeyValue('fontSize', fontSize);
			json.writeKeyValue('textLayerID', textLayerID);
			json.writeKeyValue('textLayerMD5', textLayerMD5);
		}
	}

	public function readJSON(jsonObj:Object):Void {
		costumeName = jsonObj.costumeName;
		baseLayerID = jsonObj.baseLayerID;
		if (jsonObj.baseLayerID == null) {
			if (jsonObj.imageID) baseLayerID = jsonObj.imageID; // slightly older .sb2 format
		}
		baseLayerMD5 = jsonObj.baseLayerMD5;
		if (jsonObj.bitmapResolution) bitmapResolution = jsonObj.bitmapResolution;
		rotationCenterX = jsonObj.rotationCenterX;
		rotationCenterY = jsonObj.rotationCenterY;
		text = jsonObj.text;
		if (text != null) {
			if (Std.is(jsonObj.textRect, Array)) {
				textRect = new Rectangle(jsonObj.textRect[0], jsonObj.textRect[1], jsonObj.textRect[2], jsonObj.textRect[3]);
			}
			textColor = jsonObj.textColor;
			fontName = jsonObj.fontName;
			fontSize = jsonObj.fontSize;
			textLayerID = jsonObj.textLayerID;
			textLayerMD5 = jsonObj.textLayerMD5;
		}
	}

	public function prepareToSave():Void {
		if (oldComposite != null) computeTextLayer();
		if (baseLayerID == WasEdited) baseLayerMD5 = null; // costume was edited; recompute hash
		baseLayerID = textLayerID = -1;
		//if (baseLayerData == null) baseLayerData = PNG24Encoder.encode(baseLayerBitmap, PNGFilter.PAETH);
		//if (baseLayerMD5 == null) baseLayerMD5 = by.blooddy.crypto.MD5.hashBytes(baseLayerData) + fileExtension(baseLayerData);
		if (textLayerBitmap != null) {
			//if (textLayerData == null) textLayerData = PNG24Encoder.encode(textLayerBitmap, PNGFilter.PAETH);
			//if (textLayerMD5 == null) textLayerMD5 = by.blooddy.crypto.MD5.hashBytes(textLayerData) + '.png';
		}
	}

	private function computeTextLayer():Void {
		// When saving an old-format project, generate the text layer bitmap by subtracting
		// the base layer bitmap from the composite bitmap. (The new costume format keeps
		// the text layer bitmap only, rather than the entire composite image.)

		if (oldComposite == null || baseLayerBitmap == null) return; // nothing to do
		var diff:Dynamic = oldComposite.compare(baseLayerBitmap); // diff is 0 if oldComposite and baseLayerBitmap are identical
		if (Std.is(diff, BitmapData)) {
			var stencil:BitmapData = new BitmapData(diff.width, diff.height, true, 0);
			stencil.threshold(diff, diff.rect, new Point(0, 0), '!=', 0, 0xFF000000);
			textLayerBitmap = new BitmapData(diff.width, diff.height, true, 0);
			textLayerBitmap.copyPixels(oldComposite, oldComposite.rect, new Point(0, 0), stencil, new Point(0, 0), false);
		} else if (diff != 0) {
			trace('computeTextLayer diff: ' + diff); // should not happen
		}
		oldComposite = null;
	}

	public static function fileExtension(data:ByteArray):String {
		data.position = 6;
		if (data.readUTFBytes(4) == 'JFIF') return '.jpg';
		data.position = 0;
		var s:String = data.readUTFBytes(4);
		if (s == 'GIF8') return '.gif';
		if (s == '\x89PNG') return '.png';
		if ((s == '<?xm') || (s == '<svg')) return '.svg';
		return '.dat'; // generic data; should not happen
	}

	public function generateOrFindComposite(allCostumes:Array<Dynamic>):Void {
		// If this costume has a text layer bitmap, compute or find a composite bitmap.
		// Since there can be multiple copies of the same costume, first try to find a
		// costume with the same base and text layer bitmaps and share its composite
		// costume. This saves speeds up loading and saves memory.

		if (bitmap != null) return;
		if (textLayerBitmap == null) {  // no text layer; use the base layer bitmap
			bitmap = baseLayerBitmap;
			return;
		}
		for (c in allCostumes) {
			if ((c.baseLayerBitmap == baseLayerBitmap) &&
				(c.textLayerBitmap == textLayerBitmap) &&
				(c.bitmap != null)) {
					bitmap = c.bitmap;
					return;  // found a composite bitmap to share
				}
		}
		// compute the composite bitmap
		bitmap = baseLayerBitmap.clone();
		bitmap.draw(textLayerBitmap);
	}

}
