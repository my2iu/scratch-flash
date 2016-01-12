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

// StagePart.as
// John Maloney, November 2011
//
// This part frames the Scratch stage and supplies the UI elements around it.
// Note: The Scratch stage is a child of StagePart but is stored in an app instance variable (app.stagePane)
// since it is referred from many places.

package ui.parts;


import flash.display.*;
import flash.events.*;
import flash.text.*;
import flash.media.*;
import assets.Resources;
import scratch.*;
import translation.Translator;
import uiwidgets.*;

class StagePart extends UIPart
{

	private var readoutTextColor : Int = CSS.textColor;
	private var readoutLabelFormat : TextFormat = new TextFormat(CSS.font, 12, CSS.textColor, true);
	private var readoutFormat : TextFormat = new TextFormat(CSS.font, 10, CSS.textColor);

	private static inline var topBarHeightNormal : Int = 39;
	private static inline var topBarHeightSmallPlayerMode : Int = 26;

	private var topBarHeight : Int = topBarHeightNormal;

	private var outline : Shape;
	private var projectTitle : EditableLabel;
	private var projectInfo : TextField;
	private var versionInfo : TextField;
	private var turboIndicator : TextField;
	private var runButton : IconButton;
	private var stopButton : IconButton;
	private var fullscreenButton : IconButton;
	private var stageSizeButton : Sprite;

	private var playButton : Sprite;  // YouTube-like play button in center of screen; used by Kiosk version  
	private var userNameWarning : Sprite;  // Container for privacy warning message for projects that use username block  
	private var runButtonOnTicks : Int;

	// x-y readouts
	private var readouts : Sprite;  // readouts that appear below the stage  
	private var xLabel : TextField;
	private var xReadout : TextField;
	private var yLabel : TextField;
	private var yReadout : TextField;

	public function new(app : Scratch)
	{
		super();
		this.app = app;
		outline = new Shape();
		addChild(outline);
		addTitleAndInfo();
		addRunStopButtons();
		addTurboIndicator();
		addFullScreenButton();
		addXYReadouts();
		addStageSizeButton();
		fixLayout();
		addEventListener(MouseEvent.MOUSE_WHEEL, mouseWheel);
	}

	public static function strings() : Array<Dynamic>{
		return [
		"by", "shared", "unshared", "Turbo Mode", 
		"This project can detect who is using it, through the “username” block. To hide your identity, sign out before using the project."];
	}

	public function updateTranslation() : Void{
		turboIndicator.text = Translator.map("Turbo Mode");
		turboIndicator.x = w - turboIndicator.width - 73;
		updateProjectInfo();
	}

	public function setWidthHeight(w : Int, h : Int, scale : Float) : Void{
		this.w = w;
		this.h = h;
		if (app.stagePane != null)             app.stagePane.scaleX = app.stagePane.scaleY = scale;
		topBarHeight = computeTopBarHeight();
		drawOutline();
		fixLayout();
	}

	public function computeTopBarHeight() : Int{
		return (app.isSmallPlayer) ? topBarHeightSmallPlayerMode : topBarHeightNormal;
	}

	public function installStage(newStage : ScratchStage, showStartButton : Bool) : Void{
		var scale : Float = (app.stageIsContracted) ? 0.5 : 1;
		if ((app.stagePane != null) && (app.stagePane.parent != null)) {
			scale = app.stagePane.scaleX;
			app.stagePane.parent.removeChild(app.stagePane);
		}
		topBarHeight = computeTopBarHeight();
		newStage.x = 1;
		newStage.y = topBarHeight;
		newStage.scaleX = newStage.scaleY = scale;
		addChild(newStage);
		app.stagePane = newStage;
		if (showStartButton)             showPlayButton()
		else hidePlayButton();
	}

	public function projectName() : String{return projectTitle.contents();
	}
	public function setProjectName(s : String) : Void{projectTitle.setContents(s);
	}
	public function isInPresentationMode() : Bool{return fullscreenButton.visible && fullscreenButton.isOn();
	}

	public function exitPresentationMode() : Void{
		fullscreenButton.setOn(false);
		drawOutline();
		refresh();
	}

	public function refresh() : Void{
		readouts.visible = app.editMode;
		projectTitle.visible = app.editMode;
		projectInfo.visible = app.editMode;
		stageSizeButton.visible = app.editMode;
		turboIndicator.visible = app.interp.turboMode;
		fullscreenButton.visible = !app.isSmallPlayer;
		if (app.editMode) {
			fullscreenButton.setOn(false);
			drawStageSizeButton();
		}
		if (userNameWarning != null)             userNameWarning.visible = app.usesUserNameBlock;
		updateProjectInfo();
	}

	// -----------------------------
	// Layout
	//------------------------------

	private function drawOutline() : Void{
		var topBarColors : Array<UInt> = (app.isSmallPlayer) ? [CSS.tabColor, CSS.tabColor] : CSS.titleBarColors;

		var g : Graphics = outline.graphics;
		g.clear();
		UIPart.drawTopBar(g, topBarColors, UIPart.getTopBarPath(w - 1, topBarHeight), w, topBarHeight, CSS.borderColor);
		g.lineStyle(1, CSS.borderColor, 1, true);
		g.drawRect(0, topBarHeight - 1, w - 1, h - topBarHeight);

		versionInfo.visible = !fullscreenButton.isOn();
	}

	private function fixLayout() : Void{
		if (app.stagePane != null)             app.stagePane.y = topBarHeight;

		projectTitle.x = 50;
		projectTitle.y = (app.isOffline) ? 8 : 2;
		projectInfo.x = projectTitle.x + 3;
		projectInfo.y = projectTitle.y + 18;

		runButton.x = w - 60;
		runButton.y = Std.int((topBarHeight - runButton.height) / 2);
		stopButton.x = runButton.x + 32;
		stopButton.y = runButton.y + 1;

		turboIndicator.x = w - turboIndicator.width - 73;
		turboIndicator.y = (app.isSmallPlayer) ? 5 : ((app.editMode) ? 22 : 12);

		fullscreenButton.x = 11;
		fullscreenButton.y = stopButton.y - 1;

		// version info (only used on old website player)
		versionInfo.x = fullscreenButton.x + 1;
		versionInfo.y = 27;

		projectTitle.setWidth(Std.int(runButton.x - projectTitle.x - 15));

		// x-y readouts
		var left : Int = w - 98;  // w - 95  
		xLabel.x = left;
		xReadout.x = left + 16;
		yLabel.x = left + 43;
		yReadout.x = left + 60;

		var top : Int = h + 1;
		xReadout.y = yReadout.y = top;
		xLabel.y = yLabel.y = top - 2;

		stageSizeButton.x = w - 4;
		stageSizeButton.y = h + 2;

		if (playButton != null)             playButton.scaleX = playButton.scaleY = app.stagePane.scaleX;
	}

	private function addTitleAndInfo() : Void{
		var fmt : TextFormat = (app.isOffline) ? new TextFormat(CSS.font, 16, CSS.textColor) : CSS.projectTitleFormat;
		projectTitle = getProjectTitle(fmt);
		addChild(projectTitle);

		addChild(projectInfo = UIPart.makeLabel("", CSS.projectInfoFormat));

		var versionFormat : TextFormat = new TextFormat(CSS.font, 9, 0x909090);
		addChild(versionInfo = UIPart.makeLabel(Scratch.versionString, versionFormat));
	}

	private function getProjectTitle(fmt : TextFormat) : EditableLabel{
		return new EditableLabel(null, fmt);
	}

	public function updateVersionInfo(newVersion : String) : Void{
		versionInfo.text = newVersion;
	}

	private function addTurboIndicator() : Void{
		turboIndicator = new TextField();
		turboIndicator.defaultTextFormat = new TextFormat(CSS.font, 11, CSS.buttonLabelOverColor, true);
		turboIndicator.autoSize = TextFieldAutoSize.LEFT;
		turboIndicator.selectable = false;
		turboIndicator.text = Translator.map("Turbo Mode");
		turboIndicator.visible = false;
		addChild(turboIndicator);
	}

	private function addXYReadouts() : Void{
		readouts = new Sprite();
		addChild(readouts);

		xLabel = UIPart.makeLabel("x:", readoutLabelFormat);
		readouts.addChild(xLabel);
		xReadout = UIPart.makeLabel("-888", readoutFormat);
		readouts.addChild(xReadout);

		yLabel = UIPart.makeLabel("y:", readoutLabelFormat);
		readouts.addChild(yLabel);
		yReadout = UIPart.makeLabel("-888", readoutFormat);
		readouts.addChild(yReadout);
	}

	private function updateProjectInfo() : Void{
		projectTitle.setEditable(false);
		projectInfo.text = "";
	}

	// -----------------------------
	// Stepping
	//------------------------------

	public function step() : Void{
		updateRunStopButtons();
		if (app.editMode)             updateMouseReadout();
	}

	private function updateRunStopButtons() : Void{
		// Update the run/stop buttons.
		// Note: To ensure that the user sees at least a flash of the
		// on button, it stays on a minimum of two display cycles.
		if (app.interp.threadCount() > 0)             threadStarted()
		else {  // nothing running  
			if (runButtonOnTicks > 2) {
				runButton.turnOff();
				stopButton.turnOn();
			}
		}
		runButtonOnTicks++;
	}

	private var lastX : Int;private var lastY : Int;

	private function updateMouseReadout() : Void{
		// Update the mouse readouts. Do nothing if they are up-to-date (to minimize CPU load).
		if (stage.mouseX != lastX) {
			lastX = app.stagePane.scratchMouseX();
			xReadout.text = Std.string(lastX);
		}
		if (stage.mouseY != lastY) {
			lastY = app.stagePane.scratchMouseY();
			yReadout.text = Std.string(lastY);
		}
	}

	// -----------------------------
	// Run/Stop/Fullscreen Buttons
	//------------------------------

	public function threadStarted() : Void{
		runButtonOnTicks = 0;
		runButton.turnOn();
		stopButton.turnOff();
		if (playButton != null)             hidePlayButton();
	}

	private function addRunStopButtons() : Void{
		function startAll(b : IconButton) : Void{playButtonPressed(b.lastEvent);
		};
		function stopAll(b : IconButton) : Void{app.runtime.stopAll();
		};
		runButton = new IconButton(startAll, "greenflag");
		runButton.actOnMouseUp();
		addChild(runButton);
		stopButton = new IconButton(stopAll, "stop");
		addChild(stopButton);
	}

	private function addFullScreenButton() : Void{
		function toggleFullscreen(b : IconButton) : Void{
			app.setPresentationMode(b.isOn());
			drawOutline();
		};
		fullscreenButton = new IconButton(toggleFullscreen, "fullscreen");
		fullscreenButton.disableMouseover();
		addChild(fullscreenButton);
	}

	private function addStageSizeButton() : Void{
		function toggleStageSize(evt : Dynamic) : Void{
			app.toggleSmallStage();
		};
		stageSizeButton = new Sprite();
		stageSizeButton.addEventListener(MouseEvent.MOUSE_DOWN, toggleStageSize);
		drawStageSizeButton();
		addChild(stageSizeButton);
	}

	private function drawStageSizeButton() : Void{
		var g : Graphics = stageSizeButton.graphics;
		g.clear();

		// draw tab
		g.lineStyle(1, CSS.borderColor);
		g.beginFill(CSS.tabColor);
		g.moveTo(10, 0);
		g.lineTo(3, 0);
		g.lineTo(0, 3);
		g.lineTo(0, 13);
		g.lineTo(3, 15);
		g.lineTo(10, 15);

		// draw arrow
		g.lineStyle();
		g.beginFill(CSS.arrowColor);
		if (app.stageIsContracted) {
			g.moveTo(3, 3.5);
			g.lineTo(9, 7.5);
			g.lineTo(3, 12);
		}
		else {
			g.moveTo(8, 3.5);
			g.lineTo(2, 7.5);
			g.lineTo(8, 12);
		}
		g.endFill();
	}

	// -----------------------------
	// Play Button
	//------------------------------

	private function showPlayButton() : Void{
		// The play button is a YouTube-like button the covers the entire stage.
		// Used by the player to ensure that the user clicks on the SWF to start
		// the project, which ensures that the SWF gets keyboard focus.
		if (playButton == null) {
			playButton = new Sprite();
			playButton.graphics.beginFill(0, 0.3);
			playButton.graphics.drawRect(0, 0, 480, 360);
			var flag : Bitmap = Resources.createBmp("playerStartFlag");
			flag.x = (480 - flag.width) / 2;
			flag.y = (360 - flag.height) / 2;
			playButton.alpha = .9;
			playButton.addChild(flag);
			playButton.addEventListener(MouseEvent.MOUSE_DOWN, stopEvent, false, 9);
			playButton.addEventListener(MouseEvent.MOUSE_UP, playButtonPressed, false, 9);
			addUserNameWarning();
		}
		playButton.scaleX = playButton.scaleY = app.stagePane.scaleX;
		playButton.x = app.stagePane.x;
		playButton.y = app.stagePane.y;
		addChild(playButton);
	}

	private function stopEvent(e : Event) : Void{
		if (e != null) {
			e.stopImmediatePropagation();
			e.preventDefault();
		}
	}

	public function addUserNameWarning() : Void{
		userNameWarning = new Sprite();
		var g : Graphics = userNameWarning.graphics;
		g.clear();
		g.beginFill(CSS.white);
		g.drawRoundRect(10, 30, playButton.width - 20, 70, 15, 15);
		g.endFill();
		userNameWarning.alpha = 0.9;

		var versionFormat : TextFormat = new TextFormat(CSS.font, 16, 0x000000);
		var userNameWarningText : TextField = UIPart.makeLabel(Translator.map("This project can detect who is using it, through the “username” block. To hide your identity, sign out before using the project."), versionFormat, 15, 45);
		userNameWarningText.width = userNameWarning.width - 10;
		userNameWarningText.multiline = true;
		userNameWarningText.wordWrap = true;

		userNameWarning.addChild(userNameWarningText);
		playButton.addChild(userNameWarning);

		userNameWarning.visible = false;
	}

	public function playButtonPressed(evt : MouseEvent) : Void{
		if (app.loadInProgress) {
			stopEvent(evt);
			return;
		}  // Mute the project if it was started with the control key down  



		SoundMixer.soundTransform = new SoundTransform((evt != null && (evt.ctrlKey) ? 0 : 1));

		if (evt != null && evt.shiftKey) {
			app.toggleTurboMode();
			return;
		}

		var firstTime : Bool = playButton != null;
		hidePlayButton();
		stopEvent(evt);
		app.runtime.startGreenFlags(firstTime);
	}

	public function hidePlayButton() : Void{
		if (playButton != null)             removeChild(playButton);
		playButton = null;
	}

	private function mouseWheel(evt : MouseEvent) : Void{
		evt.preventDefault();
		app.runtime.startKeyHats(evt.delta > (0) ? 30 : 31);
	}
}
