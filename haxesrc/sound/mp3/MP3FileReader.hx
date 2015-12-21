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

package sound.mp3;
	import flash.utils.*;

class MP3FileReader {

	private static inline var versionTable:Array<Float> = [2.5, -1, 2, 1];
	private static inline var layerTable:Array<Int> = [-1, 3, 2, 1];
	private static inline var samplingRateTable:Array<Int> = [44100, 48000, 32000];
	private static inline var bitRateTable1:Array<Int> = [-1, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1];
	private static inline var bitRateTable2:Array<Int> = [-1, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1];

	public var mp3Data:ByteArray;
	private var currentPosition:Int;

	// Info take from first valid MP3 header word:
	private var firstHeader:Int;
	private var version:Float;
	private var layer:Int;
	private var samplingRate:Int;
	private var channels:Int;
	private var bitRateTable:Array<Int>;
	private var bitRateMultiplier:Int;

	public function MP3FileReader(data:ByteArray) {
		mp3Data = data;
		mp3Data.position = 0;
		skipInitialTags();
		findFirstFrame();
		currentPosition = mp3Data.position;
	}

	public function swfFormatByte():Int {
		// Return the SWF format byte:
		//	4 bits: Compression type (2 = mp3, 3 = uncompressed)
		//	2 bits: Sampling rate (0 = 5512.5, 1 = 11025, 2 = 22050, 3 = 44100)
		//	1 bit: Sample size (0 = 8-bit, 1 = 16-bit)
		//	1 bit: Stereo flag (0 = mono, 1 = stereo)
		var samplingRateIndex:Int = 4 - (44100 / samplingRate);
		return (2 << 4) + (samplingRateIndex << 2) + (1 << 1) + (channels - 1);
	}

	public function appendFrame(swf:ByteArray):Int {
		mp3Data.position = currentPosition;
		if (mp3Data.bytesAvailable < 4) return 0; // end of file
		var header:UInt = mp3Data.readInt();
		if (!checkHeader(header)) return 0; // bad header (possibly a trailing id3v1 tag)
		var frameSize:Int = getFrameSize(header);
		if ((currentPosition + frameSize) > mp3Data.length) return 0; // incomplete final frame
		swf.writeBytes(mp3Data, currentPosition, frameSize);
		currentPosition += frameSize;
		return frameSize;
	}

	public function getInfo():Object {
		// Return an object with information about this MP3 file:
		//		samplingRate, channels, sampleCount, mpegVersion
		// Note: sampleCount does not take into account a partially
		// full final frame, so may overestimate slightly.
		var oldEndian:String = mp3Data.endian;
		mp3Data.endian = Endian.BIG_ENDIAN;
		mp3Data.position = 0;
		skipInitialTags();
		findFirstFrame();
		var frameCount:Int;
		while (mp3Data.bytesAvailable > 4) {
			var header:UInt = mp3Data.readInt();
			if (!checkHeader(header)) break; // bad header (possibly a trailing id3v1 tag)
			frameCount++;
			mp3Data.position += getFrameSize(header) - 4;
		}
		if (frameCount == 0) samplingRate = channels = version = 0; // bad mp3 file
		mp3Data.endian = oldEndian;
		return {
			samplingRate: samplingRate,
			channels: channels,
			sampleCount: frameCount * ((version == 1) ? 1152 : 576),
			mpegVersion: version
		}	
	}

	private function skipInitialTags():Void {
		// Skip zero or more id3v1 and/or id3v2 tags. (Some mp3 files begin with multiple tags.)
		while (mp3Data.bytesAvailable > 10) {
			var startPos:Int = mp3Data.position;
			var tag:String = mp3Data.readUTFBytes(3);
			if (tag == 'ID3') {
				mp3Data.position += 3;
				var b3:Int = mp3Data.readByte();
				var b2:Int = mp3Data.readByte();
				var b1:Int = mp3Data.readByte();
				var b0:Int = mp3Data.readByte();
				if ((b0 | b1 | b2 | b3) & 0x80) {
					mp3Data.position = startPos;
					return; // invalid ID3; high bit of every size byte must be zero
				}
				var len:Int = (b3 << 21) + (b2 << 14) + (b1 << 7) + b0;
				mp3Data.position += len;
			} else if (tag == 'TAG') {
				mp3Data.position += 125; // TAG is 128 bytes total
			} else {
				mp3Data.position = startPos;
				return;
			}
		}
	}

	private function findFirstFrame():Void {
		// Scan for a valid mp3 frame header. To guard against false positives,
		// verify that the next frame also begins with a valid header. Note
		// this means that a single frame won't be detected. (But a single-frame
		// mp3 files would not be very useful).

		while (mp3Data.bytesAvailable > 4) {
			var b:Int = mp3Data.readByte() & 0xFF;
			if (b == 0xFF) {
				mp3Data.position -= 1;
				var frameStart:Int = mp3Data.position;
				var header:Int = mp3Data.readInt();
				if (isValidHeader(header)) {
					var frameSize:Int = getFrameSize(header);
					if ((frameSize > 0) && ((mp3Data.position + frameSize + 4) < mp3Data.length)) {
						mp3Data.position = frameStart + getFrameSize(header);
						if (isValidHeader(mp3Data.readInt())) {
							firstHeader = header;
							parseHeader(firstHeader);
							mp3Data.position = frameStart;
							return;
						}
					}
				}
				mp3Data.position = frameStart + 1;
			}
		}
	}

	private function checkHeader(header:Int):Bool {
		// Return true if the given header matches the first header.
		// Ignore header fields that may differ between frames (e.g. bitRate, padding).
		return ((header ^ firstHeader) & 0xFFFF0C0C) == 0;
	}

	private function parseHeader(header:Int):Void {
		version = versionTable[getVersionIndex(header)];
		layer = layerTable[getLayerIndex(header)];
		channels = (getModeIndex(header) > 2) ? 1 : 2;
		samplingRate = samplingRateTable[getRateIndex(header)];
		if (version == 2) samplingRate /= 2;
		if (version == 2.5) samplingRate /= 4;
		bitRateTable = (version == 1) ? bitRateTable1 : bitRateTable2;
		bitRateMultiplier = (version == 1) ? 144000 : 72000;
	}

	private function getFrameSize(header:Int):Int {
		if (!firstHeader) parseHeader(header);
		var bitRate:Int = bitRateTable[getBitrateIndex(header)];
		var unpaddedSize:Int = (bitRateMultiplier * bitRate) / samplingRate;
		return unpaddedSize + getPaddingBit(header);
	}

	private function isValidHeader(header:Int):Bool {
		return ((getFrameSync(header) == 2047) &&
				(getVersionIndex(header)	!=  1) &&
				(getLayerIndex(header)		==  1) && // index 1 is layer 3
				(getBitrateIndex(header)	!=  0) &&
				(getBitrateIndex(header)	!= 15) &&
				(getRateIndex(header)		!=  3) &&
				(getEmphasisIndex(header)	!=  2));
	}

	private function getFrameSync(h:Int):Int { return (h >> 21) & 2047; }
	private function getVersionIndex(h:Int):Int { return (h >> 19) & 3; }
	private function getLayerIndex(h:Int):Int { return (h >> 17) & 3; }
	private function getCRCFlag(h:Int):Int { return (h >> 16) & 1; }
	private function getBitrateIndex(h:Int):Int { return (h >> 12) & 15; }
	private function getRateIndex(h:Int):Int { return (h >> 10) & 3; }
	private function getPaddingBit(h:Int):Int { return (h >> 9) & 1; }
	private function getModeIndex(h:Int):Int { return (h >> 6) & 3; }
	private function getEmphasisIndex(h:Int):Int { return h & 3; }

}
