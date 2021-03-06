# music.rb is symbolic musical computation for Ruby.
# Copyright (C) 2008 Jeremy Voorhis <jvoorhis@gmail.com>
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

require 'prelude'
require 'forwardable'
require 'music/duration'
require 'music/pitch'
require 'music/key'
require 'music/interpreter'
require 'music/score'
require 'music/env'
require 'music/timeline'
require 'music/smf_writer'

module Music
  include Duration
  include Score
  
  module_function
  
=begin

Pitch conversion utilities.

The standard mtof and ftom functions are defined. In both of these functions,
Hertz is represented by Float, and midi pitch is represented by Integer. Two
additional helpers are also defined: Hertz and MidiPitch. Hertz accepts both
kinds of Integer and Float, but treats Integer values as midi pitch. Float
values are assumed to be in Hertz, and are not converted. The advantage is that
they can be used to implement MusicObject interpreters where Note's pitch
representation is polymorphic. 

=end
  
  # Convert midi note numbers to hertz.
  def mtof(pitch)
    440.0 * (2.0 ** ((pitch.to_f-69)/12))
  end
  
  # Convert hertz to midi note numbers.
  def ftom(pitch)
    (69 + 12 * (Math.log2(pitch / 440.0))).round
  end
  
  # Convert a midi pitch value to Hertz.
  def Hertz(pitch)
    case pitch
      when Integer then mtof(pitch)
      when Float then pitch
      else raise ArgumentError, "Cannot cast #{pitch.class} to hertz."
    end
  end
  
=begin

Music constructors.

A piece of music may be constructed by calling note(), rest(), rest() and
group(). It is recommended that you use these methods rather than instantiating
the Score objects directly, e.g. via Music::Objects::Note.new. These functions
are both more convenient, and decouple your composition from the underlying
representation, which is subject to change.

=end
  
  # Arrange a note.
  def note(pit, dur = 1, attrs = {})
    case pit
      when Enumerable
        pit.map { |p| note(p, dur, attrs) }
      else
        Note.new(pit, dur, attrs)
    end
  end
  alias n note
  
  # Arrange a Rest.
  def rest(dur = 1, attrs = {})
    Rest.new(dur, attrs)
  end
  alias r rest
  
  # Arrange a group.
  def group(mus, attrs)
    Group.new(mus, attrs)
  end
  alias grp group
  
  # A blank arrangement of zero length. This is the identity for parallel
  # and serial composition.
  def none; rest(0) end

=begin

Music combinators.

seq() and par() both accept Enumerable lists of Scores, and combine
them into a new Score.

=end
  
  # Compose a list of arrangements sequentially.
  def s(*args)
    args[0].is_a?(Array) ? s(*args[0]) : args.inject(&:&)
  end
  
  def sn(pit, dur = 1, attrs = {})
    s(n(pit, dur, attrs))
  end
  
  # Compose a list of arrangements in parallel.
  def p(*args)
    args[0].is_a?(Array) ? p(*args[0]) : args.inject(&:|)
  end
  
  def pn(pit, dur = 1, attrs = {})
    p(n(pit, dur, attrs))
  end

=begin

Attribute generators.

Attribute generators are functions which are granted access to the context
under which a score is interpreted.

=end
  
  def env(&fn) Env.new(&fn) end

=begin

Controllers.

Controllers are instructions to the performer. They have a duration of zero.

=end
  
  def ctl(name, attrs = {})
    Controller.new(name, attrs)
  end
end
