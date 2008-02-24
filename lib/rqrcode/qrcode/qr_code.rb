#!/usr/bin/env ruby

#--
# Copyright 2004 by Duncan Robertson (duncan@whomwah.com).
# All rights reserved.

# Permission is granted for use, copying, modification, distribution,
# and distribution of modified versions of this work as long as the
# above copyright notice is included.
#++

module RQRCode #:nodoc:

  QRMODE = {
    :mode_number		=> 1 << 0,
    :mode_alpha_num	=> 1 << 1,
    :mode_8bit_byte	=> 1 << 2,
    :mode_kanji			=> 1 << 3
  }

  QRERRORCORRECTLEVEL = {
    :l => 1,
    :m => 0,
    :q => 3,
    :h => 2
  }

  QRMASKPATTERN = {
    :pattern000 => 0,
    :pattern001 => 1,
    :pattern010 => 2,
    :pattern011 => 3,
    :pattern100 => 4,
    :pattern101 => 5,
    :pattern110 => 6,
    :pattern111 => 7
  }

	# Generic QRCode exception class.

	class QRCodeArgumentError < ArgumentError; end
	class QRCodeRunTimeError < RuntimeError; end

	# This is the main interface for creating your QRCode
	# You create a new instance of QRCode and then you have
	# a few simple methods to choose form

  class QRCode
    attr_reader :modules, :module_count

    PAD0 = 0xEC
    PAD1 = 0x11	

		# Expects a string to be parsed in, other options have defaults

    def initialize( *args )
			raise QRCodeArgumentError unless args.first.kind_of?( String )

			@data									= args.shift
			options								= args.extract_options!
      level									= options[:level] || :h 
      @error_correct_level  = QRERRORCORRECTLEVEL[ level.to_sym ] 
      @type_number	        = options[:size] || 4
			@module_count					= @type_number * 4 + 17
      @modules							= nil
      @data_cache						= nil
			@data_list						= QR8bitByte.new( @data )

			self.make # let's go !
    end

		# called parsing in a row and col coordinate
		# * return true or false
		# * raise exception if row < 0 
		# * raise exception if col < 0 
		# * raise exception if @module_count <= row 
		# * raise exception if @module_count <= col 

    def is_dark( row, col )
      if row < 0 || @module_count <= row || col < 0 || @module_count <= col
        raise QRCodeRunTimeError, "#{row},#{col}"
      end
      @modules[row][col]
    end

    def to_console( row = 'x', col = ' ' )
			res = []
      @modules.each_index do |c|
        tmp = []
        @modules.each_index do |r|
          if is_dark(c,r)
            tmp << row 
          else
            tmp << col 
          end
        end 
        res << tmp.join
      end
			res.join("\n")
    end

		protected

		def make #:nodoc:
      make_impl( false, get_best_mask_pattern )
		end

		private


    def make_impl( test, mask_pattern ) #:nodoc:
      @modules = Array.new( @module_count )

      ( 0...@module_count ).each do |row|
        @modules[row] = Array.new( @module_count )
      end

      setup_position_probe_pattern( 0, 0 )
      setup_position_probe_pattern( @module_count - 7, 0 )
      setup_position_probe_pattern( 0, @module_count - 7 )
      setup_position_adjust_pattern
      setup_timing_pattern
      setup_type_info( test, mask_pattern )
      setup_type_number( test ) if @type_number >= 7

      if @data_cache.nil?
        @data_cache = QRCode.create_data( 
          @type_number, @error_correct_level, @data_list 
        ) 
      end

      map_data( @data_cache, mask_pattern )
    end


    def setup_position_probe_pattern( row, col ) #:nodoc:
      ( -1..7 ).each do |r|
        next if ( row + r )  <= -1 || @module_count <= ( row + r )
        ( -1..7 ).each do |c|
          next if ( col + c ) <= -1 || @module_count <= ( col + c )
          if 0 <= r && r <= 6 && ( c == 0 || c == 6 ) || 0 <= c && c <= 6 && ( r == 0 || r == 6 ) || 2 <= r && r <= 4 && 2 <= c && c <= 4
            @modules[row + r][col + c] = true;
          else
            @modules[row + r][col + c] = false;
          end
        end
      end
    end


    def get_best_mask_pattern #:nodoc:
      min_lost_point = 0
      pattern = 0

      ( 0...8 ).each do |i|
        make_impl( true, i )
        lost_point = QRUtil.get_lost_point( self )

        if i == 0 || min_lost_point > lost_point
          min_lost_point = lost_point
          pattern = i
        end
      end
      pattern
    end


    def setup_timing_pattern #:nodoc:
      ( 8...@module_count - 8 ).each do |r|
        next unless @modules[r][6].nil?
        @modules[r][6] = (r % 2 == 0)
      end

      ( 8...@module_count - 8 ).each do |c|
        next unless @modules[6][c].nil?
        @modules[6][c] = (c % 2 == 0)
      end
    end


    def setup_position_adjust_pattern #:nodoc:
      pos = QRUtil.get_pattern_position(@type_number)

      ( 0...pos.size ).each do |i|
        ( 0...pos.size ).each do |j|
          row = pos[i]
          col = pos[j]

          next unless @modules[row][col].nil?

          ( -2..2 ).each do |r|
            ( -2..2 ).each do |c|
              if r == -2 || r == 2 || c == -2 || c == 2 || ( r == 0 && c == 0 )
                @modules[row + r][col + c] = true
              else
                @modules[row + r][col + c] = false
              end
            end
          end	
        end
      end
    end


    def setup_type_number( test ) #:nodoc:
      bits = QRUtil.get_bch_type_number( @type_number )

      ( 0...18 ).each do |i|
        mod = ( !test && ( (bits >> i) & 1) == 1 )
        @modules[ (i / 3).floor ][ i % 3 + @module_count - 8 - 3 ] = mod
      end

      ( 0...18 ).each do |i|
        mod = ( !test && ( (bits >> i) & 1) == 1 )
        @modules[ i % 3 + @module_count - 8 - 3 ][ (i / 3).floor ] = mod
      end
    end


    def setup_type_info( test, mask_pattern ) #:nodoc:
      data = (@error_correct_level << 3 | mask_pattern)
      bits = QRUtil.get_bch_type_info( data )

      # vertical
      ( 0...15 ).each do |i|
        mod = (!test && ( (bits >> i) & 1) == 1)

        if i < 6
          @modules[i][8] = mod
        elsif i < 8
          @modules[ i + 1 ][8] = mod
        else
          @modules[ @module_count - 15 + i ][8] = mod
        end

      end

      # horizontal
      ( 0...15 ).each do |i|
        mod = (!test && ( (bits >> i) & 1) == 1)

        if i < 8
          @modules[8][ @module_count - i - 1 ] = mod
        elsif i < 9
          @modules[8][ 15 - i - 1 + 1 ] = mod
        else
          @modules[8][ 15 - i - 1 ] = mod
        end
      end

      # fixed module
      @modules[ @module_count - 8 ][8] = !test	
    end


    def map_data( data, mask_pattern ) #:nodoc:
      inc = -1
      row = @module_count - 1
      bit_index = 7
      byte_index = 0

      ( @module_count - 1 ).step( 1, -2 ) do |col|
        col = col - 1 if col <= 6

        while true do
          ( 0...2 ).each do |c|

            if @modules[row][ col - c ].nil?
              dark = false
              if byte_index < data.size
                dark = (( (data[byte_index]).rszf( bit_index ) & 1) == 1 )
              end
              mask = QRUtil.get_mask( mask_pattern, row, col - c )
              dark = !dark if mask
              @modules[row][ col - c ] = dark
              bit_index -= 1

              if bit_index == -1
                byte_index += 1
                bit_index = 7
              end
            end
          end

          row += inc

          if row < 0 || @module_count <= row
            row -= inc
            inc = -inc
            break
          end
        end
      end	
    end

    def QRCode.create_data( type_number, error_correct_level, data_list ) #:nodoc:
      rs_blocks = QRRSBlock.get_rs_blocks( type_number, error_correct_level )
      buffer = QRBitBuffer.new

      data = data_list
      buffer.put( data.mode, 4 )
      buffer.put( 
        data.get_length, QRUtil.get_length_in_bits( data.mode, type_number ) 
      )
      data.write( buffer )	

      total_data_count = 0
      ( 0...rs_blocks.size ).each do |i|
        total_data_count = total_data_count + rs_blocks[i].data_count	
      end

      if buffer.get_length_in_bits > total_data_count * 8
        raise QRCodeRunTimeError, 
					"code length overflow. (#{buffer.get_length_in_bits}>#{total_data_count})"
      end

      if buffer.get_length_in_bits + 4 <= total_data_count * 8
        buffer.put( 0, 4 )
      end

      while buffer.get_length_in_bits % 8 != 0
        buffer.put_bit( false )
      end

      while true
        break if buffer.get_length_in_bits >= total_data_count * 8
        buffer.put( QRCode::PAD0, 8 )
        break if buffer.get_length_in_bits >= total_data_count * 8
        buffer.put( QRCode::PAD1, 8 )
      end

      QRCode.create_bytes( buffer, rs_blocks )
    end


    def QRCode.create_bytes( buffer, rs_blocks ) #:nodoc:
      offset = 0
      max_dc_count = 0
      max_ec_count = 0
      dcdata = Array.new( rs_blocks.size )
      ecdata = Array.new( rs_blocks.size )

      ( 0...rs_blocks.size ).each do |r|
        dc_count = rs_blocks[r].data_count
        ec_count = rs_blocks[r].total_count - dc_count
        max_dc_count = [ max_dc_count, dc_count ].max
        max_ec_count = [ max_ec_count, ec_count ].max
        dcdata[r] = Array.new( dc_count ) 

        ( 0...dcdata[r].size ).each do |i|
          dcdata[r][i] = 0xff & buffer.buffer[ i + offset ] 
        end

        offset = offset + dc_count
        rs_poly = QRUtil.get_error_correct_polynomial( ec_count )
        raw_poly = QRPolynomial.new( dcdata[r], rs_poly.get_length - 1 )
        mod_poly = raw_poly.mod( rs_poly )
        ecdata[r] = Array.new( rs_poly.get_length - 1 )
        ( 0...ecdata[r].size ).each do |i|
          mod_index = i + mod_poly.get_length - ecdata[r].size
          ecdata[r][i] = mod_index >= 0 ? mod_poly.get( mod_index ) : 0
        end
      end

      total_code_count = 0
      ( 0...rs_blocks.size ).each do |i|
        total_code_count = total_code_count + rs_blocks[i].total_count
      end

      data = Array.new( total_code_count )
      index = 0

      ( 0...max_dc_count ).each do |i|
        ( 0...rs_blocks.size ).each do |r|
          if i < dcdata[r].size
            index += 1
            data[index-1] = dcdata[r][i]			
          end	
        end
      end

      ( 0...max_ec_count ).each do |i|
        ( 0...rs_blocks.size ).each do |r|
          if i < ecdata[r].size
            index += 1
            data[index-1] = ecdata[r][i]			
          end	
        end
      end

      data
    end 

  end

end
