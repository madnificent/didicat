module ActiveSparql
  # = ActiveSparql::Base
  #
  # Contains raw and basic support for building a graph-based model.
  #
  # ActiveSparql bases itself on ActiveModel, so you should expect
  # similar support from this class.  Note that not all supporting
  # methods have been implemented so you might need some workarounds
  # in practice.
  class Base
    include ActiveModel::Model
    attr_accessor :id

    # Indicates that this class has been persisted.  Objects which
    # have a representation in the database are said to be persisted.
    @persisted

    # General configuration for this class.  Can be used to store
    # things like the base_uri of the class.
    @@config = { :base_uri => "" }

    # Constructs a new instance, see ActiveModel::Model for more info.
    def initialize(*args)
      @persisted = false
      super
    end

    # Saves the object to the database.
    def save
      self.id = klass.generate_identifier unless persisted? || id
      save_graph = RDF::Graph.new
      fill_save_graph save_graph
      Db.insert_data( save_graph , :graph => klass.object_graph )
      persist!
    end

    # Deletes the object from the database.
    def destroy
      save_graph = RDF::Graph.new
      fill_save_graph save_graph
      save_graph.each do |s|
        puts s.inspect
      end
      Db.delete_data( save_graph, :graph => klass.object_graph )
    end

    # Returns the URI of this instance, constructed from the base_uri
    # of the class and the id of this instance.
    def uri
      "#{@@config[:base_uri]}#{id}"
    end

    # Loads a stored object from the database.
    def self.load( *args )
      # fetch the classname
      args = args.map { |a| a.to_hash }
      options = args.first
      if options[:class]
        klass = Kernel.const_get options[:class].to_s
        options.delete :class
      else
        klass = self
      end

      object = klass.new *args
      object.id = options[:id]
      object.persist!
      object
    end

    # Returns all objects of this kind.
    def self.all
      result = Db.query( all_query , self.object_graph )
      result.map do |hash|
        self.load hash
      end
    end

    # Returns the objects with the supplied identifier.
    def self.find( id )
      query = find_query( id )
      result = Db.query(find_query( id ) , self.object_graph)

      merged_result = {}
      result.each do |res|
        merged_result.empty_merge! res
      end

      self.load( merged_result )
    end

    # Indicates that this object is persisted.
    def persist!
      @persisted = true
    end

    # Inherited from ActiveModel::Model.
    def persisted?
      @persisted
    end

    # This method adds support for serializers.
    def read_attribute_for_serialization(attr)
      if attr == :url
        @url.to_s
      else
        self.send(attr)
      end
    end

  protected

    # Returns the class object of the current object.
    def klass
      self.class
    end

    # Override to return a String containing the graph where objects
    # of this kind are stored.
    def self.object_graph
      raise "#{self.to_s}.object_graph should return the graph where the objects of this kind are stored."
    end

    # Override to return a String containing the query which retrieves
    # all hashes for the objects of this type.
    def self.all_query
      raise "#{self.to_s}.all_query should return the SPARQL query which returns all the hashes for all the objects of this type."
    end

    # Override to return a String containing the query which returns
    # the hash for creating the object of this type and this id.
    def self.find_query( id )
      raise "#{self.to_s}.find_query(#{id}) should return the SPARQL query which returns the hash for creating the object with type #{self.to_s} and id #{id}."
    end

    # Enters the triples which define this graph in the Peer.
    def fill_save_graph( graph )
      raise "#{self.to_s}.fill_save_graph should fill the supplied graph with the data from the object."
    end

    # Enters the triples which define this graph in the Peer.
    def fill_destroy_graph( graph )
      fill_save_graph( graph )
    end

    # Uses a UUID and the base uri to generate an ID for the supplied object.
    def self.generate_identifier
      SecureRandom.urlsafe_base64
    end

  end

end
