/**
 * mediaExtras.js
 * 
 * Provides some extra functionalities based on the HTML5 Media API.
 * 
 * mediaSequencer
 * 	Transforms a div element that contains media elements into a sequencer.
 * mediaExtraSources
 * 	 Provides extra source types to a HTML5 media element (Youtube, MP4/MP3/FLV with Flash)
 */

(function (global) {

"use strict";

/**
 * Transforms a div element that contains media elements into a sequencer.
 * 
 * The child medias can be clipped with the attributes data-clipBegin, data-clipEnd.
 * The current media type (audio or video) can be retrieved by an attribute data-currentType.
 * 
 * Example:
 * <div>
 * 	<video type="video/webm" src="video1.webm" data-clipEnd="30" />
 * 	<audio type="audio/ogg" src="audio1.ogg" data-clipBegin="10" data-clipEnd="40" />
 * 	<video type="video/webm" src="video2.webm" />
 * </div>
 * 
 * @param {Element} media Div element to transform
 * @param {Object} options Options of the sequencer (cf mediaSequencer.defaultOptions).
 */
global.mediaSequencer = function mediaSequencer(media, options) {
	options = options || {};
	for (var i in mediaSequencer.defaultOptions) (i in options) || (options[i] = mediaSequencer.defaultOptions[i]);

	var currentTime = 0,
		paused = true,
		seeking = false,
		ended = false,
		lastMuted = false,
		lastVolume = 1,
		duration = NaN,
		pendingPlay = options.autoPlay || media.hasAttribute('data-autoplay'),
		stoppedEvents = [ 'loadeddata', 'durationchange', 'volumechange' ],
		relayedEvents = [ 'playing', 'seeking', 'seeked', 'play', 'pause', 'ratechange', 'canplay' ],
		children = toArray(media.children),
		loadedMetadataCount = children.length,
		canPlayThroughCount = children.length,
		hasVideo = false,
		seekTime = NaN,
		seeking = null,
		forcedCurrent = null;

	function stopEvent (event) {
		event.stopPropagation();
	}
	function relayEvent (event) { 
		event.stopPropagation();
		createAndDispatchEvent(media, event.type);
	}

	function startToRelayEvents (event) {
		options.debug && debug(media, 'Start to relay events: %s', this.id || this);
		if (event) {
			this.removeEventListener(event.type, startToRelayEvents, false);
			event.stopPropagation();
		}
		
		currentTime = Math.min(Math.max(roundTime(this.currentTime + this.begin - this.clipBegin), this.begin), this.end - 0.001);
		forcedCurrent = this;

		this.addEventListener('timeupdate', timeupdate, false);
		this.addEventListener('ended', timeupdate, false);
		
		relayedEvents.forEach(function (relayedEvent) {
			this.removeEventListener(relayedEvent, stopEvent, false);
			this.addEventListener(relayedEvent, relayEvent, false);
		}.bind(this));
		
		if (event) {
			seeking = null;
			createAndDispatchEvent(media, 'seeked');
		}
		createAndDispatchEvent(media, 'timeupdate');
		
		if (!paused) this.play();
	}
	
	function updateCurrentChildMedia (updateTime) {
		var newCurrent = null, mediaChanged = false;
		
		for (var i=0; i<children.length; i++) {
			var child = children[i];
			if (currentTime >= child.begin && currentTime < child.end) {
				newCurrent = child;
				break;
			}
		}
		
		if (!newCurrent && currentTime != media.duration) {
			currentTime = media.duration;
			if (media.current) {
				if (!media.current.paused) media.current.pause();
				createAndDispatchEvent(media, 'ended');
			}
			media.current = null;
		}
		
		if (media.current != newCurrent) {
			options.debug && debug(media, 'New current child media: %s', newCurrent && newCurrent.id || newCurrent);
			if (media.current) {
				seeking = null;
				media.current.removeEventListener('seeked', startToRelayEvents, false);
				media.current.removeEventListener('timeupdate', timeupdate, false);
				media.current.removeEventListener('ended', timeupdate, false);
				
				relayedEvents.forEach(function (relayedEvent) {
					media.current.removeEventListener(relayedEvent, relayEvent, false);
					media.current.addEventListener(relayedEvent, stopEvent, false);
				});
				
				media.current.pause();
				var targetMedia = media.current.targetMedia || media.current;
				targetMedia.removeAttribute('data-active');
			}
			if (newCurrent) {
				var newTargetMedia = newCurrent.targetMedia || newCurrent;
				newTargetMedia.setAttribute('data-active', 'true');
				var isVideo = newTargetMedia.tagName.toLowerCase() == 'video' || newTargetMedia.getAttribute('data-type') == 'video';
				media.setAttribute('data-currentType', isVideo ? 'video' : 'audio');
			}
			mediaChanged = true;
		}
		
		if (newCurrent && (mediaChanged || updateTime)) {
			seekTime = currentTime - newCurrent.begin + newCurrent.clipBegin;
			if (newCurrent.currentTime != seekTime) {
				seeking = true;
				createAndDispatchEvent(media, 'seeking');
				newCurrent.addEventListener('seeked', startToRelayEvents, false);
				newCurrent.currentTime = seekTime;
			} else {
				startToRelayEvents.call(newCurrent);
			}
		}
		
		media.current = newCurrent;
	}

	function timeupdate (event) {
		currentTime = Math.min(Math.max(roundTime(this.currentTime + this.begin - this.clipBegin), 0), duration);
		if (!forcedCurrent) updateCurrentChildMedia();
		else {
			currentTime = Math.min(Math.max(currentTime, forcedCurrent.begin), forcedCurrent.end - 0.001);
			if (currentTime >= forcedCurrent.begin && currentTime < forcedCurrent.end) forcedCurrent = null;
		}
		event.stopPropagation();
		createAndDispatchEvent(media, 'timeupdate');
	}
	
	function canplaythrough (event) {
		if (event) event.stopPropagation();
		canPlayThroughCount--;
		if (!canPlayThroughCount && !loadedMetadataCount) {
			createAndDispatchEvent(media, 'canplaythrough');
		}
	}

	function loadedmetadata (event) {
		options.debug && debug(media, 'Child media ready: %s', this.id || this);
		
		if (event) event.stopPropagation();
		loadedMetadataCount--;
		if (!loadedMetadataCount) {
			duration = 0;
			children.forEach(function (child) {
				duration = roundTime(duration + setupChild(child, duration));
			});
			updateCurrentChildMedia(true);
			options.debug && debug(media, 'Sequencer ready');
			createAndDispatchEvent(media, 'durationchange');
			createAndDispatchEvent(media, 'loadedmetadata');
			createAndDispatchEvent(media, 'loadeddata');
			if (!canPlayThroughCount) {
				createAndDispatchEvent(media, 'canplaythrough');
			}
			if (pendingPlay) media.play();
		}
	}
	
	children.forEach(function (child) {
		if (child.readyState == 0) child.addEventListener('loadedmetadata', loadedmetadata, false);
		else loadedmetadata.call(child);
		if (child.readyState < 4) child.addEventListener('canplaythrough', canplaythrough, false);
		else canplaythrough.call(child);
		hasVideo = hasVideo || child.tagName.toLowerCase() == 'video' || child.getAttribute('data-type') == 'video';
	});
	media.setAttribute('data-type', hasVideo ? 'video' : 'audio');

	function setupChild (child, begin) {
		child.clipBegin = parseFloat(child.getAttribute('data-clipBegin')) || 0;
		child.clipEnd = parseFloat(child.getAttribute('data-clipEnd')) || child.duration;
		var clipDuration = roundTime(child.clipEnd - child.clipBegin);
		child.begin = begin;
		child.end = roundTime(begin + clipDuration);
		if (!child.targetMedia) child.currentTime = child.clipBegin;
		stoppedEvents.forEach(function (stoppedEvent) {
			child.addEventListener(stoppedEvent, stopEvent, false);
		});
		relayedEvents.forEach(function (stoppedEvent) {
			child.addEventListener(stoppedEvent, stopEvent, false);
		});
		return clipDuration;
	}

	defineProperties(media, {
		play: { value: function() {
			paused = false;
			if (currentTime == media.duration) {
				currentTime = 0;
				updateCurrentChildMedia();
			}
			if (loadedMetadataCount) pendingPlay = true;
			else if (this.current) this.current.play();
			
		}},
	
		pause: { value: function() {
			paused = true;
			if (currentTime == media.duration) {
				currentTime = 0;
				updateCurrentChildMedia();
			}
			if (this.current) this.current.pause();
		}},
		
		readyState: {
			get: function() {
				if (!canPlayThroughCount && !loadedMetadataCount) return 4;
				else if (media.current) return media.current.readyState;
				else return 0;
			}
		},
		
		paused: { get: function () {
			return paused;
		}},
		
		ended: { get: function () {
			return currentTime == media.duration;
		}},
		
		seeking: { get: function() {
				return seeking == true || (this.current && this.current.seeking);
		}},
		
		duration: { get: function() {
			return duration;
		}},
		
		currentTime: {
			get: function() {
				return currentTime;
			},
			set: function( val ) {
				if (currentTime == val) return;
				currentTime = Math.min(Math.max(roundTime(val), 0), this.duration);
				updateCurrentChildMedia(true);
			}
		},
		
		volume: {
			get: function() {
				return lastVolume;
			},
			set: function( val ) {
				if (lastVolume != val) {
					children.forEach(function(child) {
						child.volume = val;
					});
					lastVolume = val;
					createAndDispatchEvent(media, 'volumechange');
				}
				return lastVolume;
			}
		},
		
		muted: {
			get: function() {
				return lastMuted;
			},
			set: function( val ) {
				if (lastMuted != val) {
					children.forEach(function(child) {
						child.muted = val;
					});
					lastMuted = val;
					createAndDispatchEvent(media, 'volumechange');
				}
			}
		}
	});
}
mediaSequencer.defaultOptions = {
	debug: false,
	autoplay: false
}

global.mediaWrapper = function mediaWrapper (baseMedia, elementToReplace) {
	var media = document.createElement('div'),
		events = [ 'timeupdate', 'progress', 'loadstart', 'abort', 'stalled', 'error', 'emptied', 'loadedmetadata', 'loadeddata', 'canplay', 'canplaythrough', 'playing', 'waiting', 'seeking', 'seeked', 'ended', 'durationchange', 'play', 'pause', 'ratechange', 'volumechange' ]
	
	function relayEvent(event) {
		createAndDispatchEvent(media, event.type);
	}
	events.forEach(function(eventType) {
		baseMedia.addEventListener(eventType, relayEvent, false);
	});
	defineProperties (media, {
		targetMedia: { value: baseMedia },
		play: { value: function () {
			baseMedia.play();
		}},
		pause: { value: function () {
			baseMedia.pause();
		}},
		readyState: { get: function () {
			return baseMedia.readyState;
		}},
		paused: { get: function () {
			return baseMedia.paused;
		}},
		seeking: { get: function () {
			return baseMedia.seeking;
		}},
		duration: {	get: function () {
			return baseMedia.duration;
		}},
		ended: { get: function () {
			return baseMedia.ended;
		}},
		currentTime: {
			get: function () {
				return baseMedia.currentTime;
			},
			set: function (val) {
				return baseMedia.currentTime = val;
			}
		},
		volume: {
			get: function () {
				return baseMedia.volume;
			},
			set: function (val) {
				return baseMedia.volume = val;
			}
		},
		muted: {
			get: function () {
				return baseMedia.muted;
			},
			set: function (val) {
				return baseMedia.muted = val;
			}
		},
	});
	if (elementToReplace) {
		Array.prototype.forEach.call(elementToReplace.attributes, function (attribute) {
			var attrName = attribute.nodeName; 
			if (attrName == 'id' || attrName == 'class' || attrName.indexOf('data-') == 0) media.setAttribute(attrName, attribute.nodeValue);
		});
		elementToReplace.parentNode.replaceChild(media, elementToReplace);
	}
	return media;
}

/**
 * Provides extra source types to a HTML5 media element (Youtube, MP4/MP3/FLV with Flash)
 * 
 * The media element is replaced by a div containing a flash object (the id, class and data attributes are preserved).
 * Controls are not supported.
 * 
 * Example:
 * <video width="427" height="240">
 * 	<source type="video/webm" src="video.webm" />
 * 	<source type="video/x-youtbe" src="http://www.youtube.com/watch?v=YE7VzlLtp-4" />
 * 	<source type="video/x-flv" src="video.webm" />
 * </video>
 * 
 * @param {Element|Array|NodeList|String} medias Element or list of elements (as array or css selector) to process.
 * @param {Object} options Options of the med (cf mediaExtraSources.defaultOptions).
 * @param {Function} callback Function to execute when the extra source is ready
 */
global.mediaExtraSources = function mediaExtraSources (medias, options, callback) {
	options = options || {};
	for (var i in mediaExtraSources.defaultOptions) (i in options) || (options[i] = mediaExtraSources.defaultOptions[i]);

	if (typeof medias == 'string') medias = toArray(document.querySelectorAll(medias));
	else if (medias.length) medias =  toArray(medias);
	else medias = [ medias ];


	medias.forEach(function (media) {
		var sourcesCount;
		
		function onLoadStart (event) {
			if (media.currentSrc) {
				this.removeEventListener('loadstart', onLoadStart, false);
				this.removeEventListener('error', onError, true);
				callback && callback(media);
			}
		}
		
		function onError (event) {
			if (mediaExtraSources.mediasWithError.indexOf(media) != -1) {
				this.removeEventListener('loadstart', onLoadStart, false);
				this.removeEventListener('error', onError, true);
				setupExtraSources(this, options, callback);
			}
		}
		if (media.currentSrc) callback && callback(media);
		else if (!media.canPlayType || mediaExtraSources.mediasWithError.indexOf(media) != -1) setupExtraSources(media, options, callback);
		else {
			sourcesCount = media.hasAttribute('src') ? 1 : media.querySelectorAll('source').length;
			media.addEventListener('loadstart', onLoadStart, false);
			media.addEventListener('error', onError, true);
		}
	});
};
mediaExtraSources.defaultOptions = {
		swfUri: './FlashMediaElement.swf',
		debug: false,
		debugFlash: false
}
mediaExtraSources.mediasWithError = [];

global.document.addEventListener('error', function (event) {
	if (event.target.localName == 'video' || event.target.localName == 'audio') mediaExtraSources.mediasWithError.push(event.target);
	else {
		var parent = event.target.parentNode;
		if (event.target == parent.lastElementChild && (parent.localName == 'video' || parent.localName == 'audio')) {
			mediaExtraSources.mediasWithError.push(parent);
		}
	}
}, true);

function setupExtraSources (media, options, callback) {
		var sources = media.hasAttribute('src') ? [ media ] : toArray(media.querySelectorAll('source'));
		if (!sources.some(function (source) {
			try {
				var type = source.getAttribute('type');
				if (setupExtraSources.flashVideoTypes.indexOf(type) != -1) {
					setupFlashMedia(media, source, options, callback);
					return true;
				} else if (setupExtraSources.ytVideoTypes.indexOf(type) != -1) {
					setupYoutubeMedia(media, source, options, callback);
					return true;
				}
				return false;
			} catch (e) {
				console.error(e);
				return false;
			}
		})) {
			createAndDispatchEvent(media, 'error');
		}
}
setupExtraSources.flashVideoTypes = ['video/mp4','video/m4v','video/mov','video/flv','video/x-flv','audio/flv','audio/x-flv','audio/mp3','audio/m4a','audio/mpeg' ] ;
setupExtraSources.ytVideoTypes = [ 'video/youtube', 'video/x-youtube'];

function setupFlashMedia (media, source, options, callback) {
	if (!media.id) media.id = generateId('flashMedia');
	
	var src = encodeURI(relativeURI(source.getAttribute('src'), options.swfUri)),
		readyState = 0,
		flashVars = {
			id: generateId(media.id + '_'),
			isvideo: media.tagName.toLowerCase() == 'video',
			autoplay: media.hasAttribute('autoplay'),
			preload: true, //media.getAttribute('preload'),
			debug: options.debugFlash,
			file: src
		};
	
	createMediaFlashObject(media, options.swfUri, flashVars, function (container, object) {
		defineProperties (object, {
			dispatchFlashEvent: { value: function (eventType, properties) {
				options.debug && eventType != 'timeupdate' && debug(container, 'Flash event \'%s\'', eventType);
				this._ended = false;
				this._paused = true;
				
				for (var i in properties) {
					this['_' + i] = properties[i];
				}
				
				if (eventType == 'loadedmetadata') readyState = 1;
				else if (eventType == 'playing' && readyState < 2) readyState = 2;
				else if (eventType == 'canplay' && readyState < 3) readyState = 3;
				else if (eventType == 'canplaythrough') readyState = 4;

				createAndDispatchEvent(container, eventType);
			}},
		});
		
		defineProperties (container, {
			play: { value: function () {
				object.playMedia();
			}},
			pause: { value: function () {
				object.pauseMedia();
			}},
			readyState: { get: function () {
				return readyState;
			}},
			paused: { get: function () {
					return object._paused;
			}},
			seeking: { get: function () {
				return object._seeking;
			}},
			duration: {	get: function () {
				return object._duration;
			}},
			ended: { get: function () {
				return object._ended;
			}},
			currentTime: {
				get: function () {
					return object._currentTime;
				},
				set: function (val) {
					object.setCurrentTime(val);
					return val;
				}
			},
			volume: {
				get: function () {
					return object._volume;
				},
				set: function (val) {
					object.setVolume(val);
				}
			},
			muted: {
				get: function () {
					return object._muted;
				},
				set: function (val) {
					object.setMuted(val);
				}
			},
			currentSrc: { value: src }
		});
		callback && callback(container);
	});
}

function setupYoutubeMedia (media, source, options, callback) {
	if (!media.id) media.id = generateId('youtubeMedia');
	
	var src = source.getAttribute('src'),
		objectId = generateId(media.id + '_object'),
		controls = media.hasAttribute('controls'),
		autoPlay = media.hasAttribute('autoplay'),
		videoId = /^.*(?:\/|v=)(.{11})/.exec(src)[1],
		query = (src.split("?")[1] || "").replace(/v=.{11}/, ""),
		swfUrl = "http://www.youtube.com/apiplayer?" + (query ? query + '&' : '') + "enablejsapi=1&playerapiid=" + objectId + "&version=3",
		firstPlay = true,
		duration = NaN,
		paused = true,
		seeking = false,
		seekTimeout = NaN,
		seekStates = -1,
		seekTime = NaN,
		updateInterval = NaN,
		lastUpdate = NaN,
		lastVolume = NaN,
		readyState = 0,
		oldOnYouTubePlayerReady
	
			
	if (!window.onYouTubePlayerReady) {
		var existingYoutubeHandler = window.onYouTubePlayerReady;
		window.onYouTubePlayerReady = function(objectId) {
			if (existingYoutubeHandler) existingYoutubeHandler(objectId);
			createAndDispatchEvent(document.getElementById(objectId).parentNode, 'YTPlayerReady');
		};
	}
	
	createMediaFlashObject(media, swfUrl, { id: objectId }, function (container, object) {
		container.addEventListener('YTPlayerReady', function () {
			options.debug && debug(container, 'Player ready');
			object.addEventListener('onStateChange', 'YTPlayer_' + object.id + '_onStateChange');
			object.addEventListener('onError', 'YTPlayer_' + object.id + '_onError');
			callback && callback(container);
		}, false);

		
		function timeupdate () {
			createAndDispatchEvent(container, "timeupdate");
		}

		window['YTPlayer_' + object.id + '_onStateChange'] = function (state) {
			options.debug && debug(container, 'State change: %s', state, seekStates);
			if (state == -1) {
				// unstarted
				this.loadVideoById(videoId);
			} else if (state == 0) {
				// ended
				createAndDispatchEvent(container, "timeupdate");
				clearInterval(updateInterval);
				createAndDispatchEvent(container, "ended");
			} else if (state == 1 && firstPlay) {
				// loaded (playing and firstPlay) 
				duration = this.getDuration();
				readyState = 4;
				createAndDispatchEvent(container, "durationchange");
				createAndDispatchEvent(container, "loadedmetadata");
				createAndDispatchEvent(container, "loadeddata");
				createAndDispatchEvent(container, "canplay");
				createAndDispatchEvent(container, "canplaythrough");
				
				if (autoPlay) {
					createAndDispatchEvent(container, "play");
					createAndDispatchEvent(container, "playing");
					timeupdate();
					paused = false;
				} else this.pauseVideo();
			} else if (state == 1 && !firstPlay) {
				// playing
				paused = false;
				createAndDispatchEvent(container, "playing");
				clearInterval(updateInterval);
				updateInterval = setInterval(timeupdate, 200);
			} else if (state == 2) {
				clearInterval(updateInterval);
				if (seekStates) seekStates--;
				if (seekStates == 1) {
					// seeking from a play state
					this.seekTo(seekTime);
				} else if (seekStates == 0) {
					// seeked
					seekTimeout = setTimeout(function () {
						seeking = false;
						createAndDispatchEvent(container, "seeked");
						createAndDispatchEvent(container, "timeupdate");
						if (!paused) object.playVideo();
					}, 100);
				} else if (seekStates == -1 && paused && !firstPlay) {
					// paused
					createAndDispatchEvent(container, "pause");
					createAndDispatchEvent(container, "timeupdate");
				}
				firstPlay = false;
			}
		}.bind(object);

		window['YTPlayer_' + object.id + '_onError'] = function () {
			createAndDispatchEvent(container, 'error');
		}.bind(object);
		
		defineProperties (container, {
			readyState: { get: function () {
				return readyState;
			}},
			play: { value: function () {
				var wasPaused = paused;
				paused = false;
				if (wasPaused) createAndDispatchEvent(container, "play");
				object.playVideo();
			}},
			pause: { value: function () {
				paused = true;
				object.pauseVideo();
			}},
			paused: { get: function () {
					return paused;
			}},
			seeking: { get: function () {
					return seeking;
			}},
			duration: { get: function () {
				return duration;
			}},
			ended: { get: function () {
				return object.getPlayerState() == 0;
			} },
			currentTime: {
				get: function () {
					return object.getCurrentTime();
				},
				set: function (val) {
				clearTimeout(seekTimeout);
					val = Math.max(Math.min(val, object.getDuration()), 0);
					if (val != object.getCurrentTime()) {
						if (!seeking) {
							seeking = true;
							createAndDispatchEvent(container, "seeking");
						} else  clearTimeout(seekTimeout);
						
						if (paused) {
							seekStates = 1;
							object.seekTo(val);
						} else {
							seekStates = 2;
							seekTime = val;
							object.pauseVideo();
						}
					}
					return val;
				}
			},
			volume: {
				get: function () {
					return object.getVolume() / 100;
				},
				set: function (val) {
					val = val * 100;
					if (val != object.getVolume()) {
						object.setVolume(val);
						createAndDispatchEvent(container, "volumechange");
						return val;
					}
				}
			},
			muted: {
				get: function () {
					return object.isMuted();
				}, 
				set: function (val) {
					if (val != object.isMuted()) {
						if (val) object.mute(); else object.unMute();
						createAndDispatchEvent(container, "volumechange");
						return val;
					}
				}
			},
			currentSrc: { value: src }
		});
	});
}

function createMediaFlashObject (media, swfUri, flashVars, callback) {
	var objectId = flashVars && flashVars.id || generateId(media.id + '_'),
		container = document.createElement('div'),
		altContent = document.createElement('p'),
		width = Math.max(media.width || media.clientWidth, 20),
		height = Math.max(media.height || media.clientHeight, 20);
		
	Array.prototype.forEach.call(media.attributes, function (attribute) {
		var attrName = attribute.nodeName; 
		if (attrName == 'id' || attrName == 'class' || attrName.indexOf('data-') == 0) container.setAttribute(attrName, attribute.nodeValue);
	});
	container.setAttribute('data-type', media.tagName.toLowerCase());
	container.style.width = width + 'px';
	container.style.height = height + 'px';
	altContent.id = objectId;
	container.appendChild(altContent);
	media.parentNode.replaceChild(container, media);
	
	swfobject.embedSWF(swfUri, objectId, width, height, '9', undefined, flashVars, createMediaFlashObject.flashParams, { id: objectId, name: objectId }, function (result) {
		if (result.success) callback(container, result.ref)
		else createAndDispatchEvent(container, 'error');
	});
}
createMediaFlashObject.flashParams = {
	wmode: "opaque",
	allowScriptAccess: "always",
	allowFullScreen: true
}

function roundTime (time) {
	return Math.round(time  * 1000) / 1000;
}
function defineProperties (object, descriptors) {
	Object.keys(descriptors).forEach(function(property) {
		var descriptor = descriptors[property];
		if (descriptor.enumerable === undefined) descriptor.enumerable = true;
	});
	Object.defineProperties(object, descriptors);
}

function generateId (prefix) {
	var id;
	do {
		id = (prefix || "id") + (generateId.counter++ || '')
	} while (document.getElementById(id));
   return id;
};
generateId.counter = 0;
 
function createAndDispatchEvent (element, eventType, bubbles, cancelable) {
	var event = document.createEvent('Event');
	event.initEvent(eventType, true, true);
	element.dispatchEvent(event);
}

function toArray(object) {
	if (Object.prototype.toString.call(object) == '[object Array]') return object;
	else return Array.prototype.map.call(object, function (item) { return item; });
}


function relativeURI (uri, baseUri) {
	var url = relativeURI.getURL(uri), baseUrl = relativeURI.getURL(baseUri);
	if (url.protocol == baseUrl.protocol && url.hostname == baseUrl.hostname) {
		var pathParts = url.pathname.split('/'), basePathParts = baseUrl.pathname.split('/');
		for (var i=0; pathParts[i] == basePathParts[i]; i++);
		pathParts = pathParts.slice(i);
		for (var j=i; j<basePathParts.length-1; j++) pathParts.unshift('..');
		return pathParts.join('/');
	} else return url.href;
}
relativeURI.getURL = function (uri) {
	var a = relativeURI.getURL.a;
	a.href = uri;
	return {
		hash: a.hash, host: a.host, hostname: a.hostname, href: a.href,
		pathname: a.pathname, protocol: a.protocol, search: a.search
	};
}
relativeURI.getURL.a = document.createElement('a');

function debug() {
	var media = arguments[0],
		message = arguments[1],
		params = Array.prototype.slice.call(arguments, 2),
		args = [ '[%s#%s] ' + message, media.id, media.currentTime ].concat(params);
	console.log.apply(console, args);
}
})(window);
