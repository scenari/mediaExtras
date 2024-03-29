﻿
package htmlelements
{

	public interface IMediaElement {

		function play():void;

		function pause():void;

		function load():void;

		function setSrc(url:String):void;

		function setCurrentTime(pos:Number):void;

		function setVolume(vol:Number):void;

		function setMuted(muted:Boolean):void;

		function duration():Number;

		function currentTime():Number;

	}

}