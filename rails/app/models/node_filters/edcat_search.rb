#
# == Search Filter
#
# This filter performs a search and dispatches to each friend and
# which could provide answers to the search.
#
# For both friends and kittens, a search is performed on the catalog
# level.  If any catalogs were returned, the peer is locked and will
# be queried when the filter is executed.
class NodeFilters::EdcatSearch < NodeFilter

  def contact_friend?( request , friend )
    retrieve_nodes request.params
    @friends.include? friend.url
  end

  def contact_kitten?( request , kitten )
    retrieve_nodes request.params
    @kittens.include? kitten.url
  end

  def make_filter_key( request )
    # accept any catalog which has one or more relevant catalogs
    filter_method = Proc.new do |base_url|
      begin
        url = "#{base_url}/catalogs/search"
        options = { query: request.query_parameters }
        response = JSON.parse HTTParty.get( url , options ).body
        response.class == Array && response.length > 0
      rescue
        false
      end
    end

    # send the query to each of our kittens
    # If a kitten responds: keep it
    kittens = Kitten.all.select do |kitten|
      filter_method.call kitten.url
    end

    # and to each of the friends
    # If a friend responds: keep it
    friends = Friend.all.select do |friend|
      filter_method.call "#{friend.url}/edcat"
    end

    # Save all in the database
    key = SecureRandom.urlsafe_base64
    constraints = ["didicat:filterKey \"#{key}\""]
    if kittens.length > 0
      kitten_urls = kittens.each.collect { |k| "<#{k.url}>" }
      constraints << "didicat:kitten #{kitten_urls.join(', ')}"
    end

    if friends.length > 0
      friend_urls = friends.each.collect { |f| "<#{f.url}>" }
      constraints << "didicat:friend #{friend_urls.join(', ')}"
    end

    query = <<-QUERY
        PREFIX didicat: <http://didicat.semte.ch/v0.1/>
        PREFIX filters: <http://didicat.semte.ch/v0.1/filters/>
        WITH <#{self.class.object_graph.to_s}>
        INSERT DATA {
          filters:#{key} #{constraints.join(";\n\t")}.
        }
      QUERY
    Db.update( query )
  end

protected

  # Calling this method ensures the cache of kittens and friends to
  # be contacted has been set up correctly.
  def retrieve_nodes( request_params )
    unless request_params[:filter_key]
      @kittens ||= Kitten.all.collect { |k| k.url.to_s }
      @friends ||= Friend.all.collect { |k| k.url.to_s }
    else
      kittens_query = <<QUERY
PREFIX didicat: <http://didicat.semte.ch/v0.1/>
SELECT DISTINCT ?contact_url
WHERE {
  ?filter_instance didicat:filterKey "#{request_params[:filter_key]}";
                   didicat:kitten ?contact_url.
}
QUERY

      friends_query = <<QUERY
PREFIX didicat: <http://didicat.semte.ch/v0.1>
SELECT DISTINCT ?contact_url
WHERE {
  ?filter_instance didicat:filterKey "#{request_params[:filter_key]}";
                   didicat:friend ?contact_url.
}
QUERY

      @kittens ||= Db.query( kittens_query , self.class.object_graph ).map { |k| k[:contact_url].to_s }
      @friends ||= Db.query( friends_query , self.class.object_graph ).map { |f| f[:contact_url].to_s }
    end
  end

end