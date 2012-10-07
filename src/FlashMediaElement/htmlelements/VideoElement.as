package htmlelements
{
	import flash.display.Sprite;
	import flash.events.*;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.media.Video;
	import flash.media.SoundTransform;
	import flash.utils.Timer;
	import flash.utils.setTimeout;
	import flash.utils.clearTimeout;

	import FlashMediaElement;
	import HtmlMediaEvent;

	public class VideoElement extends Sprite implements IMediaElement 
	{
		private var _src:String = "";
		private var _autoplay:Boolean = true;
		private var _preload:String = "";

		private var _connection:NetConnection;
		private var _stream:NetStream;
		private var _video:Video;
		private var _element:FlashMediaElement;
		private var _soundTransform;
		private var _oldVolume:Number = 1;

		// event values
		private var _duration:Number = NaN;
		private var _framerate:Number;
		private var _isPaused:Boolean = true;
		private var _isEnded:Boolean = false;
		private var _volume:Number = 1;
		private var _isMuted:Boolean = false;

		private var _bytesLoaded:Number = 0;
		private var _bytesTotal:Number = 0;
		private var _bufferEmpty:Boolean = true;

		private var _videoWidth:Number = -1;
		private var _videoHeight:Number = -1;

		private var _timer:Timer;
		private var _seekTimeout:Number = NaN;

		private var _isRTMP:Boolean = false;
		private var _isConnected:Boolean = false;
		private var _playWhenConnected:Boolean = false;
		private var _readyToPlay:Boolean = false;
		private var _firedCanPlayThrough:Boolean = false;
		private var _firedLoadedMetadata:Boolean = false;

		public function get video():Video {
			return _video;
		}

		public function get videoHeight():Number {
			return _videoHeight;
		}

		public function get videoWidth():Number {
			return _videoWidth;
		}

		public function duration():Number {
			return _duration;
		}
		
		public function currentTime():Number {
			return _stream ? _stream.time : 0;
		}

		// (1) load()
		// calls _connection.connect(); 
		// waits for NetConnection.Connect.Success
		// _stream gets created


		public function VideoElement(element:FlashMediaElement, autoplay:Boolean, preload:String, timerRate:Number, startVolume:Number) 
		{
			_element = element;
			_autoplay = autoplay;
			_volume = startVolume;
			_preload = preload;

			_video = new Video();
			addChild(_video);

			_connection = new NetConnection();
			_connection.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
			_connection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);

			_timer = new Timer(timerRate);
			_timer.addEventListener("timer", timerHandler);

		}

		private function timerHandler(e:TimerEvent) {
			_bytesTotal = _stream.bytesTotal;
			if (!_stream.bytesLoaded) return;
			
			if (_bytesLoaded != _stream.bytesLoaded) {
				_bytesLoaded = _stream.bytesLoaded;
				sendEvent(HtmlMediaEvent.PROGRESS);
				if (_bytesLoaded == _bytesTotal) {
					sendEvent(HtmlMediaEvent.CANPLAYTHROUGH);
				}
			}
			
			
			if (!_isPaused) sendEvent(HtmlMediaEvent.TIMEUPDATE);
		}

		// internal events
		private function netStatusHandler(event:NetStatusEvent):void {
			_element.debug("netStatus: " + event.info.code);

			switch (event.info.code) {
				case "NetConnection.Connect.Success":
					connectStream();
					break;
				case "NetStream.Play.StreamNotFound":
					_element.log("Unable to locate video: " + this._src);
					break;
				case "NetStream.Play.Start":
					if (!_isConnected) {
						_isConnected = true;
						sendEvent(HtmlMediaEvent.LOADEDDATA);
						sendEvent(HtmlMediaEvent.CANPLAY);
						_stream.pause();
						_readyToPlay = true;
						if (_playWhenConnected || _autoplay) play();
					}
					break;
				case "NetStream.Seek.Notify":
					clearTimeout(_seekTimeout);
					_seekTimeout = setTimeout(seeked, 0);
					break;
				case "NetStream.Buffer.Full":
					_bufferEmpty = false;
					break;
				case "NetStream.Buffer.Empty":
					_bufferEmpty = true;
					_isEnded ? sendEvent(HtmlMediaEvent.ENDED) : null;
					break;
				case "NetStream.Play.Stop":
					_isEnded = true;
					_timer.stop();
					_bufferEmpty ? sendEvent(HtmlMediaEvent.ENDED) : null;
					break;
			}
		}


		private function securityErrorHandler(event:SecurityErrorEvent):void {
			_element.log("Security Error: " + event.text);
		}

		private function asyncErrorHandler(event:AsyncErrorEvent):void {
			_element.log("Async Error: " + event.text);
		}


		private function onMetaDataHandler(info:Object):void {
			var durationChange:Boolean = _duration != info.duration;
			_duration = info.duration;
			_framerate = info.framerate;
			_videoWidth = info.width;
			_videoHeight = info.height;
			if (!_firedLoadedMetadata) {
				_firedLoadedMetadata = true;
				sendEvent(HtmlMediaEvent.LOADEDMETADATA);
			}
			if (durationChange) sendEvent(HtmlMediaEvent.DURATIONCHANGE);
		}

		// interface members
		public function setSrc(url:String):void {
			_src = url;
			_isRTMP = _src && !!_src.match(/^rtmp(s|t|e|te)?\:\/\//);
			load();
		}

		public function load():void {
			// disconnect existing stream and connection
			if (_isConnected && _stream) {
				if (_stream.time != 0) sendEvent(HtmlMediaEvent.TIMEUPDATE);
				_stream.pause();
				_stream.close();
				_connection.close();
			}
			_timer.stop();
			_isConnected = false;
			_isPaused = true;
			_duration = NaN;
			_bytesLoaded = 0;
			_bytesTotal = 0;
			_playWhenConnected = false;
			
			if (!_src) return;
			
			// in a few moments the "NetConnection.Connect.Success" event will fire
			// and call createConnection which finishes the "load" sequence
			sendEvent(HtmlMediaEvent.LOADSTART);
			_timer.start();
			// start new connection
			if (_isRTMP) {
				_connection.connect(_src.replace(/\/[^\/]+$/,"/"));
			} else {
				_connection.connect(null);
			}
		}
		

		private function connectStream():void {
			_stream = new NetStream(_connection);
					
			// explicitly set the sound since it could have come before the connection was made
			_soundTransform = new SoundTransform(_volume);
			_stream.soundTransform = _soundTransform;						
			
			_stream.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler); // same event as connection
			_stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);

			var customClient:Object = new Object();
			customClient.onMetaData = onMetaDataHandler;
			_stream.client = customClient;

			_video.attachNetStream(_stream);
			
			// start downloading without playing based on preload and play() hasn't been called)
			// I wish flash had a load() command to make this less awkward
			if (_preload != "none") {
				_stream.play(_src, 0, 0);
				 _stream.pause();
			}
			else _isConnected = true;
		}		

		public function play():void {
			if (!_isConnected) {
				_playWhenConnected = true;
				load();
				return;
			}
			
			_isPaused = false;
			
			if (_readyToPlay) {
				sendEvent(HtmlMediaEvent.PLAY);
				_timer.start();
				if (isNaN(_seekTimeout)) _stream.resume();
				sendEvent(HtmlMediaEvent.PLAYING);
			} else {
				_timer.start();
				if (_isRTMP) {
					_stream.play(_src.split("/").pop());
				} else {
					_stream.play(_src);
				}
			}
		}

		public function pause():void {
			if (!_stream) return;

			_stream.pause();

			_isPaused = true;
			sendEvent(HtmlMediaEvent.PAUSE);
			sendEvent(HtmlMediaEvent.TIMEUPDATE);
			
			if (_bytesLoaded == _bytesTotal) {
				_timer.stop();
			}
		}

		public function setCurrentTime(pos:Number):void {
			if (!_stream) return;
			if (isNaN(_seekTimeout)) sendEvent(HtmlMediaEvent.SEEKING);
			_stream.seek(pos);
		}
		
		public function seeked () { 
			_seekTimeout = NaN;
			sendEvent(HtmlMediaEvent.SEEKED);
			sendEvent(HtmlMediaEvent.TIMEUPDATE);
			if (!_isPaused) _stream.resume();
		}
		
		public function setVolume(volume:Number):void {
			if (_stream) {
				_soundTransform = new SoundTransform(volume);
				_stream.soundTransform = _soundTransform;				
			}
			
			_volume = volume;
			_isMuted = (_volume == 0);
			sendEvent(HtmlMediaEvent.VOLUMECHANGE);
		}


		public function setMuted(muted:Boolean):void {
			if (_isMuted == muted) return;

			if (muted) {
				_oldVolume = _stream ?  _stream.soundTransform.volume : _oldVolume;
				setVolume(0);
			} else {
				setVolume(_oldVolume);
			}

			_isMuted = muted;
		}


		private function sendEvent(eventName:String) {

			// calculate this to mimic HTML5
			var bufferedTime:Number = _bytesLoaded / _bytesTotal * _duration;

			var properties:Object = {
				duration: _duration, 
				framerate: _framerate,
				currentTime:  _stream ? _stream.time : 0,
				volume: _volume,
				muted: _isMuted,
				paused: _isPaused,
				ended: _isEnded,
				seeking: !isNaN(_seekTimeout),
				src: _src,
				bytesTotal: _bytesTotal,
				bufferedBytes: _bytesLoaded,
				bufferedTime: bufferedTime,
				videoWidth: _videoWidth,
				videoHeight: _videoHeight
			}

			_element.sendEvent(eventName, properties);
		}
	}
}