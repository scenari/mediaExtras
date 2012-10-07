var mediaEventTypes = [ 'loadstart', 'abort', 'stalled', 'error', 'emptied', 'loadedmetadata', 'loadeddata', 'canplay', 'canplaythrough', 'playing', 'waiting', 'seeking', 'seeked', 'ended', 'durationchange', 'play', 'pause', 'ratechange', 'volumechange' ];
function logMediaEvent (event) {
	console.info('[%s#%s] Event \'%s\'', event.target.id, event.target.currentTime, event.type);
}

document.addEventListener('DOMContentLoaded', function () {
	var native = document.getElementById('native');
	var sequencer = document.getElementById('sequencer');
	var medias = document.querySelectorAll('audio,video');
	var mediaCount = medias.length;
			mediaEventTypes.forEach(function(eventType) {
				native.addEventListener(eventType, logMediaEvent, false);
			});
	mediaExtraSources(medias, { swfUri: '../src/FlashMediaElement.swf', debug: true, debugFlash: false }, function (media) {							
		mediaCount--;
		if (!mediaCount) {
			native = document.getElementById('native');
			
			var watchedMedias = Array.prototype.map.call(document.querySelectorAll('.watched'), function(item) { return item; });
			
			watchedMedias.forEach(function(watchedMedia) {
				mediaEventTypes.forEach(function(eventType) {
					watchedMedia.addEventListener(eventType, logMediaEvent, false);
				});
			});

			
			if (sequencer) mediaSequencer(sequencer, { debug: true });
			
			native.addEventListener('play', function () {
				watchedMedias.forEach(function(media) { media.play(); });
			}, false);
			
			native.addEventListener('pause', function () {
				watchedMedias.forEach(function(media) { media.pause(); });
			}, false);
			
			native.addEventListener('seeked', function () {
				watchedMedias.forEach(function(media) { media.currentTime = native.currentTime; });
			}, false);
			
			native.addEventListener('volumechange', function () {
				watchedMedias.forEach(function(media) {
					media.muted = native.muted;
					media.volume = native.volume;
				});
			}, false);
		}
	});
}, false);