module ActiveSparql
  # = ActiveSparql::Simple
  #
  # Provides a more abstract way of defining semantic models.
  #
  # Subclass this class
  #
  # Specify the URI of this class by setting
  #
  #    @class_uri = 'http://my.class/uri
  #
  # Specify predicates by specifying the name and maybe some extras:
  #
  #    pred :name, 'http://xmlns.com/foaf/0.1/name'
  #
  # You can specify a longer path.  If this is a book resource, the
  # author could be referred to as:
  #
  #    pred :author_name, ['http://test/author','http://xmlns.com/foaf/0.1/name']
  #
  # has_one links are also supported.  You can (optionally) specify
  # the class of the linked resource, and you can specify the link as
  # you did before.
  #
  #    has_one :extractor, "http://didicat.semte.ch/v0.1/extractor", class: :information_extractor
  #
  class Simple < Base

    # The URL of the object is published, so others can use it as an
    # identifier
    attr_accessor :url

    # This is a default namespace for objects from
    # ActiveSparql::Simple
    @class_uri = "http://active-sparql.semte.ch/v0.1/simple"

    # Contains the specification of all variables as specified by ```self.pred```.
    @variables = {}
    # Contains the specification of all the has_one links as specified by ```self.has_one```.
    @has_one_links = {}

    # Retrieves the specification of the variables specified in this class.
    def self.variables
      @variables ||= {}
    end

    # Retrieves the specification of all the has_one links specified in this class.
    def self.has_one_links
      @has_one_links ||= {}
    end

    # Loads this object and all its has_one links.
    def self.load( *args )
      result = super( *args )
      has_one_links.each do |pred,options|
        klass = Kernel.const_get options[:class].to_s.classify
        url = result.send pred
        result.send( "#{pred.to_s}=".to_sym , klass.find( url ) ) if url
      end
      result
    end

    # Returns the uri of this class.
    def self.class_uri
      @class_uri
    end

    # Defines a predicate which is used to collect data.
    # eg: pred :name, "http://xmlns.com/foaf/0.1/nick"
    #     pred :author_name, ["http://something/author", "http://something/name"]
    def self.pred( sym, predicates )
      # accept one or multiple predicates
      unless predicates.instance_of? Array
        predicates = [ predicates ]
      end
      # use symbol as variable
      sym = sym.to_sym
      self.variables[sym.to_sym] = predicates.map &:to_uri
      attr_accessor sym.to_sym
    end

    # Defines a has_one link.
    # eg: has_one :combinator, "http://didicat.semte.ch/v0.1/combinator"
    #     has_one :filter, ["http://didicat.semte.ch/v0.1/filter"], class: :node_filter
    def self.has_one( attr_name, predicates, options={} )
      attr_name = attr_name.to_sym
      options[:class] ||= attr_name.to_sym
      # accept one or multiple predicates
      unless predicates.instance_of? Array
        predicates = [ predicates ]
      end
      # use symbol as variable
      attr_accessor attr_name
      self.has_one_links[attr_name] = { :predicates => predicates.map(&:to_uri) , :class => options[:class] }
    end

    # from Base#object_graph
    def self.object_graph
      Cfg.active_sparql_graph
    end

    # Override self.all so we always go through find.
    #
    # The base implementation doesn't retrieve all values.
    def self.all
      result = Db.query( all_query , self.object_graph )
      result.map do |hash|
        self.find hash["url"]
      end
    end

    # from Base#all_query
    def self.all_query
<<SPARQL
  SELECT DISTINCT ?url #{sparql_pred_variables}
  WHERE {
    { ?url a <#{self.class_uri}>. }
    #{union_pred_paths.join("\n")}
  }
SPARQL
    end

    # from Base#find_query
    def self.find_query( url )
<<SPARQL
  SELECT DISTINCT ?url ?class #{sparql_pred_variables}
  WHERE {
    FILTER( ?url = <#{url}> )
    { ?url a <#{self.class_uri}>. }
    #{union_pred_paths.join("\n")}
    UNION {
      ?url <http://active-sparql.semte.ch/v0.1/applicationClass> ?class.
    }
  }
SPARQL
    end

    # from Base#fill_save_graph
    def fill_save_graph( graph )
      # insert the information from the predicates
      predicate_connection = {[] => url.to_uri}
      klass.variables.each do |keyword, predicates|
        value = self.send keyword
        predicate_connection[predicates] = value if value != nil
      end
      # insert the information from the has_one_links
      klass.has_one_links.each do |keyword, options|
        object = self.send( keyword )
        predicate_connection[options[:predicates]] = object.url if object
      end

      predicate_connection.clone.each do |predicates , keyword|
        unless predicates == []
          # ensure anything for the path is ready to be written
          predicates.trailed_walk( include_empty: false ) do |predicates|
            unless predicate_connection.has_key? predicates
              blank_node = RDF::Node.new
              predicate_connection[predicates] = blank_node
              graph << [predicate_connection[predicates[0..-2]] , predicates[-1].to_uri, blank_node]
            end
          end
          # write the final predicate
          butlast_node = predicate_connection[predicates[0..-2]]
          last_node = predicate_connection[predicates]
          graph << [ butlast_node , predicates[-1].to_uri , last_node ]
        end
      end

      # set the class name
      graph << [url.to_uri, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type".to_uri, klass.class_uri.to_uri]
      # set the application class
      graph << [url.to_uri, "http://active-sparql.semte.ch/v0.1/applicationClass".to_uri, klass.to_s ]
      graph
    end

    # Fetchas the triples belonging to this object.
    def fetch_object_triples
      Db.query(klass.object_graph) do
<<SPARQL
  SELECT DISTINCT ?subject, ?predicate, ?object
  WHERE {
    <#{url}> !<wuk:doesntexist>* ?subject.
    ?subject ?predicate ?object.
  }
SPARQL
      end
    end

  private

    # Returns a string containing standardised variable names for all
    # sparql predicate variables.
    def self.sparql_pred_variables
      (self.variables.keys + self.has_one_links.keys).map{ |k| "?#{k.to_s}" }.join(" ")
    end

    # Returns the portion of the sparql query which describes the
    # paths to all sparql predicates.  Can be injected directly into
    # the where clause.
    def self.sparql_pred_paths
      pred_paths = []
      variables = self.variables.each do |k,v|
        pred_paths << "?url " + v.map{|v| "<#{v.to_s}>"}.join(" / ") + " ?#{k.to_s}."
      end
      links = self.has_one_links.each do |k, options|
        v = options[:predicates]
        pred_paths << "?url " + v.map{|v| "<#{v.to_s}>"}.join(" / ") + " ?#{k.to_s}."
      end
      pred_paths
    end

    # Predicates may consist of multiple unions.  This method returns
    # a list containing all unions for the paths (making sure we can
    # fetch all data).
    def self.union_pred_paths
      sparql_pred_paths.collect do |path|
        "UNION { #{path} }"
      end
    end

  end
end
