
package htmlelements 
{
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.TimerEvent;
	import flash.media.ID3Info;
	import flash.media.Sound;
	import flash.media.SoundChannel;
	import flash.media.SoundLoaderContext;
	import flash.media.SoundTransform;
	import flash.net.URLRequest;
	import flash.utils.Timer;



	/**
	* ...
	* @author DefaultUser (Tools -> Custom Arguments...)
	*/
	public class AudioElement implements IMediaElement
	{

		private var _sound:Sound;
		private var _soundTransform:SoundTransform;
		private var _soundChannel:SoundChannel;
		private var _soundLoaderContext:SoundLoaderContext;

		private var _volume:Number = 1;
		private var _preMuteVolume:Number = 0;
		private var _isMuted:Boolean = false;
		private var _isPaused:Boolean = true;
		private var _isEnded:Boolean = false;
		private var _isSeeking:Boolean = false;
		private var _isLoaded:Boolean = false;
		private var _currentTime:Number = 0;
		private var _duration:Number = NaN;

		private var _src:String = "";
		private var _autoplay:Boolean = true;
		private var _preload:String = "";

		private var _element:FlashMediaElement;
		private var _timer:Timer;
		private var _firedCanPlayThrough:Boolean = false;
		private var _firedLoadedMetadata:Boolean = false;
		private var _bytesLoaded:Number = NaN;

		public function duration():Number {
			return _duration;
		}

		public function currentTime():Number {
			return _currentTime;
		}

		public function AudioElement(element:FlashMediaElement, autoplay:Boolean, preload:String, timerRate:Number, startVolume:Number) 
		{
			_element = element;
			_autoplay = autoplay;
			_volume = startVolume;
			_preload = preload;

			_timer = new Timer(timerRate);
			_timer.addEventListener(TimerEvent.TIMER, timerEventHandler);

			_soundTransform = new SoundTransform(_volume);
			_soundLoaderContext = new SoundLoaderContext();
		}

		function timerEventHandler(e:TimerEvent) {
 			if (!_sound.bytesLoaded) return;
			
			if (_bytesLoaded != _sound.bytesLoaded) {
				_bytesLoaded = _sound.bytesLoaded;
				sendEvent(HtmlMediaEvent.PROGRESS);
			}
			
			var duration;
			if (_bytesLoaded != _sound.bytesTotal) duration =  Math.round(_sound.length * _sound.bytesTotal/_bytesLoaded) / 1000;
			else duration = Math.round(_sound.length) / 1000;
			if (_duration != duration) {
				_duration = duration;
				if (!this._firedLoadedMetadata) {
					sendEvent(HtmlMediaEvent.LOADEDMETADATA);
					this._firedLoadedMetadata = true;
				}
				sendEvent(HtmlMediaEvent.DURATIONCHANGE);
			}

			if (_bytesLoaded == _sound.bytesTotal) {
				if (!_firedCanPlayThrough) {
					_firedCanPlayThrough = true;
					sendEvent(HtmlMediaEvent.CANPLAYTHROUGH);
				}
				if (_isPaused) _timer.stop();
			}
			
			// send timeupdate
			if (_soundChannel) {
				var currentTime = _soundChannel.position/1000;
				if (_currentTime != currentTime) {
					_currentTime = currentTime;
					sendEvent(HtmlMediaEvent.TIMEUPDATE);
				}
			}
			
			// sometimes the ended event doesn't fire, here's a fake one
			if (_duration > 0 && _currentTime >= _duration-0.2) {
				handleEnded();
			} else _isEnded = false;
		}

		function soundCompleteHandler(e:Event) {
			handleEnded();
		}

		function playSound () {
			if (!_sound) return;
			stopSound();
			_soundChannel = _sound.play(_currentTime*1000, 0, _soundTransform);
			_soundChannel.addEventListener(Event.SOUND_COMPLETE, soundCompleteHandler);
		}
		
		function stopSound () {
			if (!_sound || !_soundChannel) return;
			_soundChannel.removeEventListener(Event.SOUND_COMPLETE, soundCompleteHandler);
			_soundChannel.stop();
			_soundChannel = null;
		}
		
		function handleEnded():void {
			_timer.stop();
			_currentTime = 0;
			_isEnded = true;

			sendEvent(HtmlMediaEvent.ENDED);
		}
		
		// METHODS
		public function setSrc(url:String):void {
			_src = url;
			_isLoaded = false;
			if (_preload != "none") load();
		}


		public function load():void {
			if (_soundChannel) {
				_soundChannel.stop();
				_soundChannel = null;
			}
			if (!_src) return;

			_sound = new Sound();
			_sound.load(new URLRequest(_src));
			if (_currentTime != 0) {
				_currentTime = 0;
				sendEvent(HtmlMediaEvent.TIMEUPDATE);
			}
			
			sendEvent(HtmlMediaEvent.LOADSTART);

			_isLoaded = true;
                        
			sendEvent(HtmlMediaEvent.LOADEDDATA);
			sendEvent(HtmlMediaEvent.CANPLAY);
			
			if (_playWhenLoaded) {
				_playWhenLoaded = false;
				play();
			} else {
				_timer.start();
			}
		}

		private var _playWhenLoaded:Boolean= false;

		public function play():void {
			if (!_isLoaded) {
				_playWhenLoaded = true;
				load();
				return;
			}

			playSound();
			_isPaused = false;
			_timer.start();
			sendEvent(HtmlMediaEvent.PLAY);
			sendEvent(HtmlMediaEvent.PLAYING);
		}

		public function pause():void {
			if (_isPaused) return;
			stopSound();
			_isPaused = true;
			sendEvent(HtmlMediaEvent.PAUSE);
			timerEventHandler(null);
		}
		
		public function setCurrentTime(pos:Number):void {
			this._isSeeking = true;
			sendEvent(HtmlMediaEvent.SEEKING);
			_currentTime = pos;
			playSound();
			_element.log('seek ' + _soundChannel.position/1000); 
			if (_isPaused || _isEnded) _soundChannel.stop();
			timerEventHandler(null);
			this._isSeeking = false;
			sendEvent(HtmlMediaEvent.SEEKED);
		}

		public function setVolume(volume:Number):void {
			_volume = volume;
			_soundTransform.volume = volume;

			if (_soundChannel) {
				_soundChannel.soundTransform = _soundTransform;
			}

			sendEvent(HtmlMediaEvent.VOLUMECHANGE);
		}


		public function setMuted(muted:Boolean):void {

			// ignore if already set
			if ( (muted && _isMuted) || (!muted && !_isMuted))
				return;

			if (muted) {
				_preMuteVolume = _soundTransform.volume;
				setVolume(0);
			} else {
				setVolume(_preMuteVolume);
			}

			_isMuted = muted;
		}

		private function sendEvent(eventName:String) {
			// calculate this to mimic HTML5
			var bufferedTime:Number = _sound.bytesLoaded / _sound.bytesTotal * _duration;

			var properties:Object = {
				duration: _duration, 
				currentTime: _currentTime,
				volume: _volume,
				muted: _isMuted,
				paused: _isPaused,
				ended: _isEnded,
				seeking: _isSeeking,
				src: _src,
				bytesTotal: _sound.bytesTotal,
				bufferedBytes: _sound.bytesLoaded,
				bufferedTime: bufferedTime
			}

			_element.sendEvent(eventName, properties);
		}

	}

}
