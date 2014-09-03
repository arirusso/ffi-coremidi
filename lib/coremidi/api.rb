module CoreMIDI

  # Coremidi C binding
  module API

    extend FFI::Library
    ffi_lib '/System/Library/Frameworks/CoreMIDI.framework/Versions/Current/CoreMIDI'

    # if osx is 10.6 or higher, there are some differences with 32 vs 64 bit handling
    X86_64 = `uname -r`.scan(/\d*\.\d*/).first.to_f >= 10.6

    typedef :pointer, :CFStringRef
    typedef :int32, :ItemCount
    typedef :pointer, :MIDIClientRef
    typedef :pointer, :MIDIDeviceRef
    typedef :pointer, :MIDIEndpointRef
    typedef :pointer, :MIDIEntityRef
    typedef :pointer, :MIDIObjectRef
    typedef :pointer, :MIDIPortRef
    #typedef :pointer, :MIDIReadProc
    typedef :uint32, :MIDITimeStamp
    typedef :int32, :OSStatus

    class MIDISysexSendRequest < FFI::Struct

      layout :destination,         :MIDIEndpointRef,
             :data,                :pointer,
             :bytes_to_send,       :uint32,
             :complete,            :int,
             :reserved,            [:char, 3],
             :completion_proc,     :pointer,
             :completion_ref_con,  :pointer
    end

    class MIDIPacket < FFI::Struct

      layout :timestamp, :MIDITimeStamp,
             :nothing, :uint32, # no idea...
             :length, :uint16,
             :data, [:uint8, 256]

    end

    class MIDIPacketList < FFI::Struct
      layout :numPackets, :uint32,
             :packet, [MIDIPacket.by_value, 1]

    end

    # Pack the given data into a coremidi MIDI packet (used by Destination)
    def self.pack_midi_data(data)
      format = "C" * data.size
      packed_data = data.pack(format)
      char_size = FFI.type_size(:char) * data.size
      bytes = FFI::MemoryPointer.new(char_size)
      bytes.write_string(packed_data)
      bytes
    end

    def self.create_midi_client(resource_id, name)
      client_name = API::CF.CFStringCreateWithCString(nil, "Client #{resource_id} #{name}", 0)
      client_pointer = FFI::MemoryPointer.new(:pointer)
      error = API.MIDIClientCreate(client_name, nil, nil, client_pointer)
      client = client_pointer.read_pointer
      {
        :error => error,
        :pointer => client_pointer,
        :resource => client
      }
    end

    def self.create_midi_output_port(client, resource_id, name)
      port_name = CF.CFStringCreateWithCString(nil, "Port #{resource_id}: #{name}", 0)
      port_pointer = FFI::MemoryPointer.new(:pointer)
      error = API.MIDIOutputPortCreate(client, port_name, port_pointer)
      {
        :error => error,
        :pointer => port_pointer
      }
    end

    # (used by Destination)
    def self.get_midi_packet_list(bytes, size)
      packet_list = FFI::MemoryPointer.new(256)
      packet_ptr = API.MIDIPacketListInit(packet_list)
      packet_ptr = if X86_64
        API.MIDIPacketListAdd(packet_list, 256, packet_ptr, 0, size, bytes)
      else
        # Pass in two 32-bit 0s for the 64 bit time
        API.MIDIPacketListAdd(packet_list, 256, packet_ptr, 0, 0, size, bytes)
      end
      packet_list
    end

    # @param [FFI::Pointer] resource A pointer to an underlying struct
    # @param [String, Symbol] name The property name to get
    # @return [String]
    def self.get_string(resource, name)
      property = CF.CFStringCreateWithCString(nil, name.to_s, 0)
      begin
        pointer = FFI::MemoryPointer.new(:pointer)
        MIDIObjectGetStringProperty(resource, property, pointer)
        string = pointer.read_pointer
        length = CF.CFStringGetMaximumSizeForEncoding(CF.CFStringGetLength(string), :kCFStringEncodingUTF8)

        bytes = FFI::MemoryPointer.new(length + 1)

        if CF.CFStringGetCString(string, bytes, length + 1, :kCFStringEncodingUTF8)
          bytes.read_string.force_encoding("utf-8")
        end
      ensure
        CF.CFRelease(string) unless string.nil? || string.null?
        CF.CFRelease(property) unless property.null?
      end
    end

    callback :MIDIReadProc, [MIDIPacketList.by_ref, :pointer, :pointer], :pointer

    attach_function :MIDIClientCreate, [:pointer, :pointer, :pointer, :pointer], :int

    attach_function :MIDIClientDispose, [:pointer], :int

    # MIDIEntityRef MIDIDeviceGetEntity (MIDIDeviceRef  device, ItemCount entityIndex0);
    attach_function :MIDIDeviceGetEntity, [:MIDIDeviceRef, :ItemCount], :MIDIEntityRef

    attach_function :MIDIGetNumberOfDestinations, [], :ItemCount

    attach_function :MIDIGetNumberOfDevices, [], :ItemCount

    attach_function :MIDIGetDestination, [:int], :pointer
    
    #extern OSStatus MIDIEndpointDispose( MIDIEndpointRef endpt );
    attach_function :MIDIEndpointDispose, [:MIDIEndpointRef], :OSStatus

    # MIDIEndpointRef MIDIEntityGetDestination( MIDIEntityRef entity, ItemCount destIndex0 );
    attach_function :MIDIEntityGetDestination, [:MIDIEntityRef, :int], :MIDIEndpointRef

    # ItemCount MIDIEntityGetNumberOfDestinations (MIDIEntityRef  entity);
    attach_function :MIDIEntityGetNumberOfDestinations, [:MIDIEntityRef], :ItemCount

    # ItemCount MIDIEntityGetNumberOfSources (MIDIEntityRef  entity);
    attach_function :MIDIEntityGetNumberOfSources, [:MIDIEntityRef], :ItemCount

    # MIDIEndpointRef MIDIEntityGetSource (MIDIEntityRef  entity, ItemCount sourceIndex0);
    attach_function :MIDIEntityGetSource, [:MIDIEntityRef, :ItemCount], :MIDIEndpointRef

    attach_function :MIDIGetDevice, [:ItemCount], :MIDIDeviceRef
    
    # extern OSStatus MIDIInputPortCreate( MIDIClientRef client, CFStringRef portName, 
    #                                      MIDIReadProc readProc, void * refCon, MIDIPortRef * outPort );
    attach_function :MIDIInputPortCreate, [:MIDIClientRef, :CFStringRef, :MIDIReadProc, :pointer, :MIDIPortRef], :OSStatus

    # extern OSStatus MIDIObjectGetIntegerProperty( MIDIObjectRef obj, CFStringRef propertyID, SInt32 * outValue );
    attach_function :MIDIObjectGetIntegerProperty, [:MIDIObjectRef, :CFStringRef, :pointer], :OSStatus
    # OSStatus MIDIObjectGetStringProperty (MIDIObjectRef  obj, CFStringRef propertyID, CFStringRef *str);
    attach_function :MIDIObjectGetStringProperty, [:MIDIObjectRef, :CFStringRef, :pointer], :OSStatus
                                                                                                                    
    # extern OSStatus MIDIOutputPortCreate( MIDIClientRef client, CFStringRef portName, MIDIPortRef * outPort );
    attach_function :MIDIOutputPortCreate, [:MIDIClientRef, :CFStringRef, :pointer], :int

    attach_function :MIDIPacketListInit, [:pointer], :pointer

    #extern OSStatus MIDIPortConnectSource( MIDIPortRef port, MIDIEndpointRef source, void * connRefCon )
    attach_function :MIDIPortConnectSource, [:MIDIPortRef, :MIDIEndpointRef, :pointer], :OSStatus

    #extern OSStatus MIDIPortDisconnectSource( MIDIPortRef port, MIDIEndpointRef source );
    attach_function :MIDIPortDisconnectSource, [:MIDIPortRef, :MIDIEndpointRef], :OSStatus

    #extern OSStatus MIDIPortDispose(MIDIPortRef port );
    attach_function :MIDIPortDispose, [:MIDIPortRef], :OSStatus

    #extern OSStatus MIDISend(MIDIPortRef port,MIDIEndpointRef dest,const MIDIPacketList *pktlist);
    attach_function :MIDISend, [:MIDIPortRef, :MIDIEndpointRef, :pointer], :int

    attach_function :MIDISendSysex, [:pointer], :int

    if X86_64
      attach_function :MIDIPacketListAdd, [:pointer, :int, :pointer, :int, :int, :pointer], :pointer
    else
      # extern MIDIPacket * MIDIPacketListAdd( MIDIPacketList * pktlist, ByteCount listSize, 
      #                                        MIDIPacket * curPacket, MIDITimeStamp time, 
      #                                        ByteCount nData, const Byte * data)
      attach_function :MIDIPacketListAdd, [:pointer, :int, :pointer, :int, :int, :int, :pointer], :pointer
    end

    module CF

      extend FFI::Library
      ffi_lib '/System/Library/Frameworks/CoreFoundation.framework/Versions/Current/CoreFoundation'

      typedef :pointer, :CFStringRef
      typedef :long, :CFIndex
      enum :CFStringEncoding, [ :kCFStringEncodingUTF8, 0x08000100 ]

      # CFString* CFStringCreateWithCString( ?, CString, encoding)
      attach_function :CFStringCreateWithCString, [:pointer, :string, :int], :pointer
      # CString* CFStringGetCStringPtr(CFString*, encoding)
      attach_function :CFStringGetCStringPtr, [:pointer, :int], :pointer

      attach_function :CFStringGetLength, [ :CFStringRef ], :CFIndex

      attach_function :CFStringGetMaximumSizeForEncoding, [ :CFIndex, :CFStringEncoding ], :long

      attach_function :CFStringGetCString, [ :CFStringRef, :pointer, :CFIndex, :CFStringEncoding ], :bool

      attach_function :CFRelease, [ :pointer ], :void

    end

    module HostTime
      extend FFI::Library
      ffi_lib '/System/Library/Frameworks/CoreAudio.framework/Versions/Current/CoreAudio'

      attach_function :AudioConvertHostTimeToNanos, [:uint64], :uint64
    end

  end

end
