package h2d;

import hxd.Key in K;

private typedef TextHistoryElement = {t:String, c:Int, sel:{start:Int, length:Int}};

/**
	A skinnable text input handler.

	Supports text selection, keyboard cursor navigation, as well as basic hotkeys: `Ctrl + Z`, `Ctrl + Y` for undo and redo and `Ctrl + A` to select all text.
**/
class TextInput extends Text {
	#if sys
	public static final modifierKey:Int = Sys.systemName() == "Mac" ? K.LEFT_WINDOW_KEY : K.CTRL;
	#else
	public static final modifierKey:Int = K.CTRL;
	#end

	/**
		Current position of the input cursor.
		When TextInput is not focused value is -1.
	**/
	public var cursorIndex:Int = -1;

	/**
		The Tile used to render the input cursor.
	**/
	public var cursorTile:h2d.Tile;

	/**
		The Tile used to render the background for selected text.
		When rendering, this Tile is stretched horizontally to fill entire selection area.
	**/
	public var selectionTile:h2d.Tile;

	/**
		The blinking interval of the cursor in seconds.
	**/
	public var cursorBlinkTime = 0.5;

	/**
		Maximum input width.
		Contrary to `Text.maxWidth` does not cause a word-wrap, but also masks out contents that are outside the max width.
	**/
	public var inputWidth:Null<Int>;

	/**
		When disabled, user would not be able to edit the input text (selection is still available).
	**/
	public var canEdit = true;

	/**
		If set, TextInput will render provided color as a background to text interactive area.
	**/
	public var backgroundColor(get, set):Null<Int>;

	var interactive:h2d.Interactive;
	var cursorText:String;
	var cursorX:Float;
	var cursorXIndex:Int;
	var cursorBlink = 0.;
	var cursorScroll = 0;
	var scrollX = 0.;
	var selectionPos:Float;
	var selectionSize:Float;
	var undo:Array<TextHistoryElement> = [];
	var redo:Array<TextHistoryElement> = [];
	var lastChange = 0.;
	var lastClick = 0.;
	var maxHistorySize = 100;

	/**
		Create a new TextInput instance.
		@param font The font used to render the text.
		@param parent An optional parent `h2d.Object` instance to which TextInput adds itself if set.
	**/
	public function new(font, ?parent) {
		super(font, parent);
		interactive = new h2d.Interactive(0, 0);
		interactive.cursor = TextInput;
		interactive.onPush = function(e:hxd.Event) {
			onPush(e);
			if (!e.cancel && e.button == 0) {
				if (!interactive.hasFocus()) {
					e.kind = EFocus;
					onFocus(e);
					e.kind = EPush;
					if (e.cancel)
						return;
					interactive.focus();
				}
				cursorBlink = 0;
				var startIndex = textPos(e.relX, e.relY);
				cursorIndex = startIndex;
				selectionRange = null;
				this.needsRebuild = true;

				var pt = new h2d.col.Point();
				var scene = getScene();
				if (scene == null)
					return; // was removed
				scene.startCapture(function(e) {
					pt.x = e.relX;
					pt.y = e.relY;
					globalToLocal(pt);
					var index = textPos(pt.x, pt.y);
					if (index == startIndex)
						selectionRange = null;
					else if (index < startIndex)
						selectionRange = {start: index, length: startIndex - index};
					else
						selectionRange = {start: startIndex, length: index - startIndex};
					this.needsRebuild = true;
					selectionSize = 0;
					cursorIndex = index;
					if (e.kind == ERelease || getScene() != scene)
						scene.stopCapture();
				});
			}
		};
		interactive.onKeyDown = function(e:hxd.Event) {
			onKeyDown(e);
			handleKey(e);
		};
		interactive.onTextInput = function(e:hxd.Event) {
			onTextInput(e);
			handleKey(e);
		};
		interactive.onFocusLost = function(e) {
			cursorIndex = -1;
			selectionRange = null;
			this.needsRebuild = true;
			onFocusLost(e);
		};

		interactive.onClick = function(e) {
			onClick(e);
			if (e.cancel)
				return;
			var t = haxe.Timer.stamp();
			// double click to select all
			if (t - lastClick < 0.3 && text.length != 0) {
				selectionRange = {start: 0, length: text.length};
				this.needsRebuild = true;
				selectionSize = 0;
				cursorIndex = text.length;
			}
			lastClick = t;
		};

		interactive.onKeyUp = function(e) onKeyUp(e);
		interactive.onRelease = function(e) onRelease(e);
		interactive.onFocus = function(e) onFocus(e);
		interactive.onKeyUp = function(e) onKeyUp(e);
		interactive.onMove = function(e) onMove(e);
		interactive.onOver = function(e) onOver(e);
		interactive.onOut = function(e) onOut(e);

		interactive.cursor = TextInput;

		addChildAt(interactive, 0);
	}

	override function constraintSize(width:Float, height:Float) {
		// disable (don't allow multiline textinput for now)
	}

	function handleKey(e:hxd.Event) {
		if (e.cancel || cursorIndex < 0)
			return;

		var oldIndex = cursorIndex;
		var oldText = text;

		switch (e.keyCode) {
			case K.LEFT if (K.isDown(modifierKey)):
				cursorIndex = getWordStart();
			case K.LEFT:
				if (cursorIndex > 0)
					cursorIndex--;
			case K.RIGHT if (K.isDown(modifierKey)):
				cursorIndex = getWordEnd();
			case K.RIGHT:
				if (cursorIndex < text.length)
					cursorIndex++;
			case K.HOME:
				cursorIndex = 0;
			case K.END:
				cursorIndex = text.length;
			case K.BACKSPACE, K.DELETE if (selectionRange != null):
				if (!canEdit)
					return;
				beforeChange();
				cutSelection();
				onChange();
			case K.DELETE:
				if (cursorIndex < text.length && canEdit) {
					beforeChange();
					var end = K.isDown(K.CTRL) ? getWordEnd() : cursorIndex + 1;
					text = text.substr(0, cursorIndex) + text.substr(end);
					onChange();
				}
			case K.BACKSPACE:
				if (cursorIndex > 0 && canEdit) {
					beforeChange();
					var end = cursorIndex;
					cursorIndex = K.isDown(K.CTRL) ? getWordStart() : cursorIndex - 1;
					text = text.substr(0, cursorIndex) + text.substr(end);
					onChange();
				}
			case K.ESCAPE, K.ENTER, K.NUMPAD_ENTER:
				cursorIndex = -1;
				#if (android || uwp)
				textInput(false);
				#end
				interactive.blur();
				return;
			case K.Z if (K.isDown(modifierKey)):
				if (undo.length > 0 && canEdit) {
					redo.push(curHistoryState());
					setState(undo.pop());
					onChange();
				}
				return;
			case K.Y if (K.isDown(modifierKey)):
				if (redo.length > 0 && canEdit) {
					undo.push(curHistoryState());
					setState(redo.pop());
					onChange();
				}
				return;
			case K.A if (K.isDown(modifierKey)):
				if (text != "") {
					cursorIndex = text.length;
					selectionRange = {start: 0, length: text.length};
					this.needsRebuild = true;
					selectionSize = 0;
				}
				return;
			case K.C if (K.isDown(modifierKey)):
				if (text != "" && selectionRange != null) {
					hxd.System.setClipboardText(text.substr(selectionRange.start, selectionRange.length));
				}
			case K.X if (K.isDown(modifierKey)):
				if (text != "" && selectionRange != null) {
					if (hxd.System.setClipboardText(text.substr(selectionRange.start, selectionRange.length))) {
						if (!canEdit)
							return;
						beforeChange();
						cutSelection();
						onChange();
					}
				}
			case K.V if (K.isDown(modifierKey)):
				if (!canEdit)
					return;
				var t = hxd.System.getClipboardText();
				if (t != null && t.length > 0) {
					beforeChange();
					if (selectionRange != null)
						cutSelection();
					text = text.substr(0, cursorIndex) + t + text.substr(cursorIndex);
					cursorIndex += t.length;
					onChange();
				}
			default:
				if (e.kind == EKeyDown)
					return;
				if (e.charCode != 0 && canEdit) {
					if (!font.hasChar(e.charCode))
						return; // don't allow chars not supported by font

					beforeChange();
					if (selectionRange != null)
						cutSelection();
					if (e.inputChar != "" && e.inputChar != null) {
						text = text.substr(0, cursorIndex) + e.inputChar + text.substr(cursorIndex);
						cursorIndex += e.inputChar.length;
					} else {
						text = text.substr(0, cursorIndex) + String.fromCharCode(e.charCode) + text.substr(cursorIndex);
						cursorIndex++;
					}
					onChange();
				}
		}

		cursorBlink = 0.;

		if (K.isDown(K.SHIFT) && text == oldText) {
			if (cursorIndex == oldIndex)
				return;

			if (selectionRange == null)
				selectionRange = oldIndex < cursorIndex ? {start: oldIndex, length: cursorIndex - oldIndex} : {
					start: cursorIndex,
					length: oldIndex - cursorIndex
				};
			else if (oldIndex == selectionRange.start) {
				selectionRange.length += oldIndex - cursorIndex;
				selectionRange.start = cursorIndex;
			} else
				selectionRange.length += cursorIndex - oldIndex;

			if (selectionRange.length == 0) {
				selectionRange = null;
				this.needsRebuild = true;
			} else if (selectionRange.length < 0) {
				selectionRange.start += selectionRange.length;
				selectionRange.length = -selectionRange.length;
			}
			selectionSize = 0;
		} else {
			selectionRange = null;
			this.needsRebuild = true;
		}
	}

	function cutSelection() {
		if (selectionRange == null)
			return false;
		cursorIndex = selectionRange.start;
		var end = cursorIndex + selectionRange.length;
		text = text.substr(0, cursorIndex) + text.substr(end);
		selectionRange = null;
		this.needsRebuild = true;
		return true;
	}

	function getWordEnd() {
		var len = text.length;
		if (cursorIndex >= len) {
			return cursorIndex;
		}
		var charset = hxd.Charset.getDefault();
		var ret = cursorIndex;
		while (ret < len && charset.isSpace(StringTools.fastCodeAt(text, ret)))
			ret++;
		while (ret < len && !charset.isSpace(StringTools.fastCodeAt(text, ret)))
			ret++;
		return ret;
	}

	function getWordStart() {
		if (cursorIndex <= 0) {
			return cursorIndex;
		}
		var charset = hxd.Charset.getDefault();
		var ret = cursorIndex;
		while (ret > 0 && charset.isSpace(StringTools.fastCodeAt(text, ret - 1)))
			ret--;
		while (ret > 0 && !charset.isSpace(StringTools.fastCodeAt(text, ret - 1)))
			ret--;
		return ret;
	}

	function setState(h:TextHistoryElement) {
		text = h.t;
		cursorIndex = h.c;
		selectionRange = h.sel;
		this.needsRebuild = true;
		if (selectionRange != null)
			cursorIndex = selectionRange.start + selectionRange.length;
	}

	function curHistoryState():TextHistoryElement {
		return {t: text, c: cursorIndex, sel: selectionRange == null ? null : {start: selectionRange.start, length: selectionRange.length}};
	}

	function beforeChange() {
		var t = haxe.Timer.stamp();
		if (t - lastChange < 1) {
			lastChange = t;
			return;
		}
		lastChange = t;
		undo.push(curHistoryState());
		redo = [];
		while (undo.length > maxHistorySize)
			undo.shift();
	}

	/**
		Returns a String representing currently selected text area or `null` if no text is selected.
	**/
	public function getSelectedText():String {
		return selectionRange == null ? null : text.substr(selectionRange.start, selectionRange.length);
	}

	override function set_text(t:String) {
		super.set_text(t);
		if (cursorIndex > t.length)
			cursorIndex = t.length;
		return t;
	}

	override function set_font(f) {
		super.set_font(f);
		cursorTile = h2d.Tile.fromColor(0x000000, Std.int(1 / hxd.Window.getInstance().windowToPixelRatio), font.size);
		cursorTile.dy = 2 / hxd.Window.getInstance().windowToPixelRatio;
		selectionTile = h2d.Tile.fromColor(0x3399FF, 0, hxd.Math.ceil(font.lineHeight));
		return f;
	}

	override function initGlyphs(text:String, rebuild = true):Void {
		super.initGlyphs(text, rebuild);
		if (rebuild) {
			this.calcWidth += cursorTile.width; // cursor end pos
			if (inputWidth != null && this.calcWidth > inputWidth)
				this.calcWidth = inputWidth;
		}
	}

	function textPos(x:Float, y:Float) {
		x += scrollX;
		var pos = 0;
		while (pos < text.length) {
			if (calcTextWidth(text.substr(0, pos + 1)) > x)
				break;
			pos++;
		}
		return pos;
	}

	override function sync(ctx) {
		interactive.width = (inputWidth != null ? inputWidth : maxWidth != null ? Math.ceil(maxWidth) : textWidth);
		interactive.height = font.lineHeight;
		super.sync(ctx);
	}

	override function draw(ctx:RenderContext) {
		if (inputWidth != null) {
			var h = localToGlobal(new h2d.col.Point(inputWidth, font.lineHeight));
			ctx.clipRenderZone(absX, absY, h.x - absX, h.y - absY);
		}

		if (cursorIndex >= 0 && (text != cursorText || cursorIndex != cursorXIndex)) {
			if (cursorIndex > text.length)
				cursorIndex = text.length;
			cursorText = text;
			cursorXIndex = cursorIndex;
			cursorX = calcTextWidth(text.substr(0, cursorIndex));
			if (inputWidth != null && cursorX - scrollX >= inputWidth)
				scrollX = cursorX - inputWidth + 1;
			else if (cursorX < scrollX && cursorIndex > 0)
				scrollX = cursorX - hxd.Math.imin(inputWidth, Std.int(cursorX));
			else if (cursorX < scrollX)
				scrollX = cursorX;
		}

		absX -= scrollX * matA;
		absY -= scrollX * matC;

		if (selectionRange != null) {
			if (selectionSize == 0) {
				selectionPos = calcTextWidth(text.substr(0, selectionRange.start));
				selectionSize = calcTextWidth(text.substr(selectionRange.start, selectionRange.length));
				if (selectionRange.start + selectionRange.length == text.length)
					selectionSize += cursorTile.width; // last pixel
			}
			selectionTile.dx += selectionPos;
			selectionTile.width += selectionSize;
			var hasSdf = removeShader(this.sdfShader);
			var prevColor = this.color.clone();
			this.color.set(1, 1, 1, 1);
			emitTile(ctx, selectionTile);
			if (hasSdf)
				addShader(this.sdfShader);
			this.color.load(prevColor);
			selectionTile.dx -= selectionPos;
			selectionTile.width -= selectionSize;
		}

		super.draw(ctx);
		absX += scrollX * matA;
		absY += scrollX * matC;

		if (cursorIndex >= 0) {
			cursorBlink += ctx.elapsedTime;
			if (cursorBlink % (cursorBlinkTime * 2) < cursorBlinkTime) {
				cursorTile.dx += cursorX - scrollX;
				var hasSdf = removeShader(this.sdfShader);
				var prevColor = this.color.clone();
				this.color.set(1, 1, 1, 1);
				emitTile(ctx, cursorTile);
				if (hasSdf)
					addShader(this.sdfShader);
				this.color.load(prevColor);
				cursorTile.dx -= cursorX - scrollX;
			}
		}

		if (inputWidth != null)
			ctx.popRenderZone();
	}

	/**
		Sets focus on this `TextInput`.
	**/
	public function focus() {
		var ib = interactive.getBounds();
		#if (android || uwp)
		textInput(true);
		#end
		#if android
		textInputRect(Std.int(ib.x), Std.int(ib.y), Std.int(ib.width), Std.int(ib.height));
		#end
		interactive.focus();
		if (cursorIndex < 0) {
			cursorIndex = 0;
			if (text != "") {
				selectionRange = {start: 0, length: text.length};
				this.needsRebuild = true;
			}
		}
	}

	/**
		Checks if TextInput is currently focused.
	**/
	public function hasFocus() {
		return interactive.hasFocus();
	}

	/**
		Delegate of underlying `Interactive.onOut`.
	**/
	public dynamic function onOut(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onOver`.
	**/
	public dynamic function onOver(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onMove`.
	**/
	public dynamic function onMove(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onClick`.
	**/
	public dynamic function onClick(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onPush`.
	**/
	public dynamic function onPush(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onRelease`.
	**/
	public dynamic function onRelease(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onKeyDown`.
	**/
	public dynamic function onKeyDown(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onKeyUp`.
	**/
	public dynamic function onKeyUp(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onTextInput`.
	**/
	public dynamic function onTextInput(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onFocus`.
	**/
	public dynamic function onFocus(e:hxd.Event) {}

	/**
		Delegate of underlying `Interactive.onFocusLost`.
	**/
	public dynamic function onFocusLost(e:hxd.Event) {}

	/**
		Sent when user modifies TextInput contents.
	**/
	public dynamic function onChange() {}

	override function drawRec(ctx:RenderContext) {
		var old = interactive.visible;
		interactive.visible = false;
		interactive.draw(ctx);
		super.drawRec(ctx);
		interactive.visible = old;
	}

	function get_backgroundColor()
		return interactive.backgroundColor;

	function set_backgroundColor(v)
		return interactive.backgroundColor = v;

	#if (android || uwp)
	@:hlNative("sdl", "text_input")
	public static function textInput(enable:Bool):Void {}
	#end

	#if android
	@:hlNative("sdl", "text_input_rect")
	public static function textInputRect(x:Int, y:Int, w:Int, h:Int):Void {}
	#end
}
