# music.rb is symbolic musical computation for Ruby.
# Copyright (C) 2008 Jeremy Voorhis
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class Array
  def rand
    self[(Kernel::rand * size).floor]
  end
end

module Music
  
  def self.log2(x)
    Math.log(x) / Math.log(2)
  end 
  
  # Convert midi note numbers to hertz
  def self.mtof(pitch)
    440.0 * (2 ** (((pitch)-69)/12))
  end
  
  # Convert hertz to midi note numbers
  def self.ftom(pitch)
    (69 + 12 * (log2(pitch / 440.0))).round
  end
  
  # Cast pitch value as a midi pitch number.
  def self.MidiPitch(pitch)
    case pitch
      when Integer then pitch 
      when Float then ftom(pitch)
      else raise ArgumentError, "Cannot cast #{pitch.class} to midi."
    end
  end
  
  # Cast pitch value as hertz.
  def self.Hertz(pitch)
    case pitch
      when Integer then mtof(pitch)
      when Float then pitch
      else raise ArgumentError, "Cannot cast #{pitch.class} to hertz."
    end
  end
  
  class PitchClass
    include Comparable
    
    def self.for(pitch)
      PITCH_CLASSES.detect { |pc| pc.ord == pitch % 12 }
    end
    
    attr_reader :name, :ord
    
    def initialize(name, ord)
      @name, @ord = name, ord
    end
    
    def <=>(pc) ord <=> pc.ord end
    
    def to_s; name.to_s end
    
    # Western pitch classes. Accidental note names borrowed from LilyPond.
    PITCH_CLASSES = [
      new(:c, 0), new(:cis, 1),
      new(:d, 2), new(:dis, 3),
      new(:e, 4),
      new(:f, 5), new(:fis, 6),
      new(:g, 7), new(:gis, 8),
      new(:a, 9), new(:ais, 10),
      new(:b, 1)
    ]
  end
  
  class MusicStructure
    # Sequencing
    def >>(structure)
      @next = structure
    end
    
    def has_next?
      !@next.nil?
    end
    
    def next_structure; @next end
    
    # Return the next MusicEvent in its prepared state.
    def next
      @next.prepare if @next
    end
    
    # Prepare the structure before generating an event.
    def prepare; self end
    
    def generate(surface)
      raise NotImplementedError, "Subclass responsibility"
    end
    
    def surface
      Surface.new(self)
    end
    
    def structure
      StructureIterator.new(self)
    end
  end
  
  class MusicEvent
    # Call +MusicEvent#perform+ with a performance visitor.
    def perform(performance)
      raise NotImplementedError, "Subclass responsibility"
    end
  end
  
  class Surface
    include Enumerable
    
    def initialize(head)
      @head    = head
      @surface = []
      generate
    end
    
    def [](key) @surface[key] end
    
    def each(&block) @surface.each(&block) end
    
    def generate
      @surface.clear
      return if @head.nil?
      cursor = @head
      
      begin
        @surface << cursor.generate(self)
      end while cursor = cursor.next
    end
  end
  
  class StructureIterator
    include Enumerable
    
    def initialize(head)
      @head = head
    end
    
    def each
      return if @head.nil?
      cursor = @head
      
      begin
        yield cursor
      end while cursor = cursor.next_structure
    end
  end
  
  # Remain silent for the duration.
  class Silence < MusicEvent
    attr :duration
    
    def initialize(duration)
      @duration = duration
    end
    
    def perform(performance)
      performance.play_silence(self)
    end
  end
  
  # A note has a steady pitch and a duration.
  class Note < MusicEvent
    attr_reader :pitch, :duration
    
    def initialize(pitch, duration)
      @pitch, @duration = pitch, duration
    end
    
    def perform(performance)
      performance.play_note(self)
    end
    
    def pitch_class
      PitchClass.for(@pitch)
    end
  end
  
  class Chord < MusicEvent
    attr_reader :pitches, :duration
    
    def initialize(pitches, duration)
      @pitches, @duration = pitches, duration
    end
    
    def perform(performance)
      performance.play_chord(self)
    end
    
    def pitch_class
      @pitches.map { |pitch| PitchClass.for(pitch) }
    end
  end
  
  class LiteralEvent < MusicStructure
    def initialize(event)
      @event = event
    end
    
    def generate(surface) @event.dup end
  end
  
  # Choose randomly from given structures, then proceed.
  class Choice < MusicStructure
    def initialize(*choices)
      @choices = choices
    end
    
    def prepare
      event = @choices.rand
      unless event.has_next?
        event = event.dup
        event >> @next
      end
      event.prepare
    end
  end
  
  ::Kernel.module_eval do
    def silence(duration=128)
      LiteralEvent.new(Silence.new(duration))
    end
    alias :rest :silence
    
    def note(pitch, duration=128)
      LiteralEvent.new(Note.new(pitch, duration))
    end
    
    def chord(pitches, duration=128)
      LiteralEvent.new(Chord.new(pitches, duration))
    end
    
    def choice(*events)
      Choice.new(*events)
    end
  end
  
  require 'smf'
  
  # Standard Midi File performance.
  class SMFPerformance
    include SMF
    
    def initialize(surface, seq_name)
      @surface = surface
      @filename = seq_name + '.mid'
      @seq = Sequence.new
      @track = Track.new
      @seq << @track
      @track << SequenceName.new(0, seq_name)
      @channel = 1
      @offset = 0
    end
    
    def perform
      @surface.each { |event| event.perform(self) }
      self
    end
    
    def save
      @seq.save(@filename)
    end
    
    def play_silence(ev)
      @offset += ev.duration
    end
    
    def play_note(ev)
      @track << NoteOn.new(@offset, @channel, Music.MidiPitch(ev.pitch), 64)
      @offset += ev.duration
      @track << NoteOff.new(@offset, @channel, Music.MidiPitch(ev.pitch), 64)
    end
    
    def play_chord(ev)
      for pitch in ev.pitches
        @track << NoteOn.new(@offset, @channel, Music.MidiPitch(pitch), 64)
      end
      @offset += ev.duration
      for pitch in ev.pitches
        @track << NoteOff.new(@offset, @channel, Music.MidiPitch(pitch), 64)
      end
    end
  end
end

if __FILE__ == $0
  def random_voice
    (lbl=note(60)) >> note(62) >> note(64) >> choice(lbl, note(62)) >> chord([60, 67, 72])
    lbl
  end
  
  s = random_voice.surface
  puts s.map { |note| note.pitch_class } * ', '
  
  Music::SMFPerformance.new(s, 'example').perform.save
end
