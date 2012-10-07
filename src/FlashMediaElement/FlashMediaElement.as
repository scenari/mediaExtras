package  
{
	import flash.display.*;
	import flash.events.*;
	import flash.media.*;
	import flash.net.*;
	import flash.text.*;
	import flash.system.*;

	import flash.media.Video;
	import flash.net.NetConnection;
	import flash.net.NetStream;

	import flash.filters.DropShadowFilter;
	import flash.utils.Timer;
	import flash.external.ExternalInterface;
	import flash.geom.Rectangle;

	import htmlelements.IMediaElement;
	import htmlelements.VideoElement;
	import htmlelements.AudioElement;

	public class FlashMediaElement extends MovieClip {

		private var _objectId:String;
		private var _mediaUrl:String;
		private var _autoplay:Boolean;
		private var _preload:String;
		private var _debug:Boolean;
		private var _isVideo:Boolean;
		private var _video:Video;
		private var _timerRate:Number;
		private var _stageWidth:Number;
		private var _stageHeight:Number;
		private var _enableSmoothing:Boolean;
		private var _allowedPluginDomain:String;
		private var _isFullscreen:Boolean = false;
		private var _startVolume:Number;

		// native video size (from meta data)
		private var _nativeVideoWidth:Number = 0;
		private var _nativeVideoHeight:Number = 0;

		// media
		private var _mediaElement:IMediaElement;

		// connection to fullscreen 
		private var _connection:LocalConnection;
		private var _connectionName:String;

		public function FlashMediaElement() {

			// show allow this player to be called from a different domain than the HTML page hosting the player
			Security.allowDomain("*");

			// get parameters
			var params:Object = LoaderInfo(this.root.loaderInfo).parameters;
			debug(params['timerrate']);
			_objectId = params['id'] ? params['id'] : ExternalInterface.objectID;
			_mediaUrl = params['file'] ? params['file'] : "";
			_autoplay = params['autoplay'] ? params['autoplay'] == "true" : false;
			_debug = params['debug'] ? params['debug'] == "true" : false;
			_isVideo = params['isvideo'] ? params['isvideo'] == "false" ? false : true : true;
			_timerRate = params['timerrate'] ? parseInt(params['timerrate'], 10) : 250;
			_enableSmoothing = params['smoothing'] ? params['smoothing'] == "true" : false;
			_startVolume = params['startvolume'] ? parseFloat(params['startvolume']) : 0.8;
			_preload = params['preload'] ? params['preload'] : "auto";

			if (isNaN(_timerRate)) _timerRate = 250;
			if (isNaN(_startVolume)) _startVolume = 0.8;

			// setup stage and player sizes/scales
			stage.align = StageAlign.TOP_LEFT;
			stage.scaleMode = StageScaleMode.NO_SCALE;
			_stageWidth = stage.stageWidth;
			_stageHeight = stage.stageHeight;
			
			// create media element
			if (_isVideo) {
				_mediaElement = new VideoElement(this, _autoplay, _preload, _timerRate, _startVolume);
				_video = (_mediaElement as VideoElement).video;
				_video.width = _stageWidth;
				_video.height = _stageHeight;
				_video.smoothing = _enableSmoothing;
				//_video.scaleMode = VideoScaleMode.MAINTAIN_ASPECT_RATIO;
				addChild(_video);
			} else {
				_mediaElement = new AudioElement(this, _autoplay, _preload, _timerRate, _startVolume);
			}

			debug("stage: " + stage.stageWidth + "x" + stage.stageHeight + "\n");
			debug("file: " + _mediaUrl + "\n");
			debug("autoplay: " + _autoplay.toString() + "\n");
			debug("preload: " + _preload.toString() + "\n");
			debug("isvideo: " + _isVideo.toString() + "\n");
			debug("smoothing: " + _enableSmoothing.toString() + "\n");
			debug("timerrate: " + _timerRate.toString() + "\n");
			debug("displayState: " +(stage.hasOwnProperty("displayState")).toString() + "\n");

			// attach javascript
			debug("ExternalInterface.available: " + ExternalInterface.available.toString() + "\n");
			debug("objectId: " + _objectId + "\n");

			if (_mediaUrl) _mediaElement.setSrc(_mediaUrl);

			if (ExternalInterface.available) {
				debug("Adding callbacks...\n");
				try {
					if (_objectId) {
						
						// add HTML media methods
						ExternalInterface.addCallback("playMedia", playMedia);
						ExternalInterface.addCallback("loadMedia", loadMedia);
						ExternalInterface.addCallback("pauseMedia", pauseMedia);

						ExternalInterface.addCallback("setSrc", setSrc);
						ExternalInterface.addCallback("setCurrentTime", setCurrentTime);
						ExternalInterface.addCallback("setVolume", setVolume);
						ExternalInterface.addCallback("setMuted", setMuted);
	
						ExternalInterface.addCallback("setFullscreen", setFullscreen);
						ExternalInterface.addCallback("setVideoSize", setVideoSize);
	
						// fire init method					
						//ExternalInterface.call("mejs.MediaPluginBridge.initPlugin", _objectId);
					}

					debug("Success...\n");

				} catch (error:SecurityError) {
					log("A SecurityError occurred: " + error.message + "\n");
				} catch (error:Error) {
					log("An Error occurred: " + error.message + "\n");
				}

			}

			/*if (_preload != "none") {
				_mediaElement.load();
				
				if (_autoplay) {
					_mediaElement.play();
				}
			} else if (_autoplay) {
				_mediaElement.load();
				_mediaElement.play();
			}*/




			// connection to full screen
			//_connection = new LocalConnection();
			//_connection.client = this;
			//_connection.connect(_objectId + "_player");

			// listen for rezie
			stage.addEventListener(Event.RESIZE, resizeHandler);
			
			// resize
			stage.addEventListener(FullScreenEvent.FULL_SCREEN, stageFullScreen);	
		}

		function resizeHandler(e:Event):void {
			//_video.scaleX = stage.stageWidth / _stageWidth;
			//_video.scaleY = stage.stageHeight / _stageHeight;
			//positionControls();
			_stageWidth = stage.stageWidth;
			_stageHeight = stage.stageHeight;
			repositionVideo();
		}

		function setFullscreen(goFullscreen:Boolean) {
			try {
				//_fullscreenButton.visible = false;

				if (goFullscreen) {
					var screenRectangle:Rectangle = new Rectangle(_video.x, _video.y, flash.system.Capabilities.screenResolutionX, flash.system.Capabilities.screenResolutionY); 
					stage.fullScreenSourceRect = screenRectangle;

					stage.displayState = StageDisplayState.FULL_SCREEN;
					_isFullscreen = true;
				} else {
					stage.displayState = StageDisplayState.NORMAL;
					_isFullscreen = false;
				}

			} catch (error:Error) {
				_isFullscreen = false;
				log("Fullscreen Error: " + error.toString());   
			}
		}

		function stageFullScreen(e:FullScreenEvent) {
			debug("Fullscreen event: " + e.fullScreen.toString() + "\n");   

			_isFullscreen = e.fullScreen;
		}

		function playMedia() {
			debug("playMedia\n");
			_mediaElement.play();
		}

		function loadMedia() {
			debug("loadMedia\n");
			_mediaElement.load();
		}

		function pauseMedia() {
			debug("pauseMedia\n");
			_mediaElement.pause();
		}

		function setSrc(url:String) {
			debug("setSrc: " + url + "\n");
			_mediaElement.setSrc(url);
		}

		function setCurrentTime(time:Number) {
			debug("setCurrentTime: " + time.toString() + "\n");
			_mediaElement.setCurrentTime(time);
		}

		function setVolume(volume:Number) {
			debug("setVolume: " + volume.toString() + "\n");
			_mediaElement.setVolume(volume);
		}

		function setMuted(muted:Boolean) {
			debug("setMuted: " + muted.toString() + "\n");
			_mediaElement.setMuted(muted);
		}

		function setVideoSize(width:Number, height:Number) {
			debug("setVideoSize: " + width.toString() + "," + height.toString() + "\n");

			_stageWidth = width;
			_stageHeight = height;

			if (_video) repositionVideo();
		}

		function repositionVideo(fullscreen:Boolean = false):void {

			if (_nativeVideoWidth <= 0 || _nativeVideoHeight <= 0)
				return;

			debug("positioning video\n");

			// calculate ratios
			var stageRatio, nativeRatio;
			
			_video.x = 0;
			_video.y = 0;			
			
			if(fullscreen == true) {
				stageRatio = flash.system.Capabilities.screenResolutionX/flash.system.Capabilities.screenResolutionY;
				nativeRatio = _nativeVideoWidth/_nativeVideoHeight;
	
				// adjust size and position
				if (nativeRatio > stageRatio) {
					_video.width = flash.system.Capabilities.screenResolutionX;
					_video.height = _nativeVideoHeight * flash.system.Capabilities.screenResolutionX / _nativeVideoWidth;
					_video.y = flash.system.Capabilities.screenResolutionY/2 - _video.height/2;
				} else if (stageRatio > nativeRatio) {
					_video.height = flash.system.Capabilities.screenResolutionY;
					_video.width = _nativeVideoWidth * flash.system.Capabilities.screenResolutionY / _nativeVideoHeight;
					_video.x = flash.system.Capabilities.screenResolutionX/2 - _video.width/2;
				} else if (stageRatio == nativeRatio) {
					_video.height = flash.system.Capabilities.screenResolutionY;
					_video.width = flash.system.Capabilities.screenResolutionX;

				}
			} else {
				stageRatio = _stageWidth/_stageHeight;
				nativeRatio = _nativeVideoWidth/_nativeVideoHeight;
	
				// adjust size and position
				if (nativeRatio > stageRatio) {
					_video.width = _stageWidth;
					_video.height = _nativeVideoHeight * _stageWidth / _nativeVideoWidth;
					_video.y = _stageHeight/2 - _video.height/2;
				} else if (stageRatio > nativeRatio) {
					_video.height = _stageHeight;
					_video.width = _nativeVideoWidth * _stageHeight / _nativeVideoHeight;
					_video.x = _stageWidth/2 - _video.width/2;
				} else if (stageRatio == nativeRatio) {
					_video.height = _stageHeight;
					_video.width = _stageWidth;
				}
			}
		}

		// SEND events to JavaScript
		public function sendEvent(eventName:String, properties:Object) {
			// special video event
			if (eventName == HtmlMediaEvent.LOADEDMETADATA && _isVideo) {
				_nativeVideoWidth = (_mediaElement as VideoElement).videoWidth;
				_nativeVideoHeight = (_mediaElement as VideoElement).videoHeight;

				repositionVideo();
			}

			if (_objectId) {
				if (_isVideo) properties.isFullscreen = _isFullscreen;
				
				var jsonProperties:String = "{";
				for (var propName in properties) {
					if (jsonProperties != "{") jsonProperties += ',';
					jsonProperties += '"' + propName + '":';
					if (properties[propName] is String) jsonProperties += '"' + properties[propName] + '"';
					else jsonProperties += properties[propName];
				}
				jsonProperties += "}";
				//debug(eventName + " " + jsonProperties);
				// use set timeout for performance reasons
				ExternalInterface.call("setTimeout", "document.getElementById('" + _objectId + "').dispatchFlashEvent('" + eventName + "'," + jsonProperties + ")",0);
			}
		}


		public function debug (... arguments) {
			if (_debug) log.apply(this, arguments);
		}
		
		public function log (... arguments) {
			ExternalInterface.call("console && console.log", "[[" + _objectId + "#" + _mediaElement.duration() + "]] " + arguments.join(' '));
		}
	}
}