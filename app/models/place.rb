class Place
  include Mongoid::Document
  include ActiveModel::Model
  attr_accessor :id, :formatted_address, :location, :address_components

  #Init variables
  def initialize(params={})
    @id = params[:_id].to_s
    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
    @address_components = params[:address_components].map{ |a| AddressComponent.new(a)} if !params[:address_components].nil?
  end

  #Shortcut to default database
  def self.mongo_client
  	db = Mongo::Client.new('mongodb://localhost:27017')
  end

  #Returns db collection holding Places
  def self.collection
  	self.mongo_client['places']
  end

  #Loads JSON document and places info into places document
  def self.load_all(file)
  	docs = JSON.parse(file.read)
  	collection.insert_many(docs)
  end

  #Finds collection by short name
  def self.find_by_short_name(short_name)
    collection.find(:'address_components.short_name' => short_name)
  end

  #Returns collection of place objects
  def self.to_places(places)
    places.map do |place|
      Place.new(place)
    end
  end
  
  #Finds instance of place based on id
  def self.find(id)
    id = BSON::ObjectId.from_string(id)
    doc = collection.find(:_id => id).first

    if doc.nil?
      return nil
    else
      return Place.new(doc)
    end
  end

  #Returns collection of all documents as places
  def self.all(offset = 0, limit = nil)
    result = collection.find({}).skip(offset)
    result = result.limit(limit) if !limit.nil?
    result = to_places(result)
  end

  #Delete document
  def destroy
    id = BSON::ObjectId.from_string(@id)
    self.class.collection.delete_one(:_id => id)
  end

  #Gets collection of address components from document
  def self.get_address_components(sort = nil, offset = 0, limit = nil)
    prototype = [
      {
        :$unwind => '$address_components'
      },
      {
        :$project => {
          :address_components => 1,
          :formatted_address => 1,
          :'geometry.geolocation' => 1
        }
      }
    ]

    prototype << {:$sort => sort} if !sort.nil?
    prototype << {:$skip => offset} if offset != 0
    prototype << {:$limit => limit} if !limit.nil?

    collection.find.aggregate(prototype)
  end

  #Return array of country names from collection
  def self.get_country_names
    prototype = [
      {
        :$unwind => '$address_components'
      },
      {
        :$project => {
          :'address_components.long_name' => 1,
          :'address_components.types' => 1
        }
      },
      {
        :$match => {
          :"address_components.types" => "country"
        }
      },
      {
        :$group => {
          :"_id" => '$address_components.long_name'
        }
      }
    ]

    result = collection.find.aggregate(prototype)

    result.to_a.map {|doc| doc[:_id]}
  end

  #Find id of country code
  def self.find_ids_by_country_code(country_code)
    prototype = [
      {
        :$match => {
          :"address_components.types" => "country",
          :"address_components.short_name" => country_code
        }
      },
      {
        :$project => {
          :_id => 1
        }
      }
    ]

    result = collection.find.aggregate(prototype)
    result.to_a.map {|doc| doc[:_id].to_s }
  end

  #Create 2dsphere indexes for geometry.geolocation method
  def self.create_indexes
    collection.indexes.create_one(:'geometry.geolocation' => Mongo::Index::GEO2DSPHERE)
  end

  #Remove 2dspehre indexes
  def self.remove_indexes
    collection.indexes.drop_one('geometry.geolocation_2dsphere')
  end

  #Returns closest places to point
  def self.near(point, max_meters= nil)
    query = {
      :'geometry.geolocation' => {
        :$near => {
          :$geometry => point.to_hash,
          :$maxDistance => max_meters
        }
      }
    }

    collection.find(query)
  end

  #Locates all places by near
  def near(max_meters=nil)
    result = self.class.near(@location, max_meters)
    self.class.to_places(result)
  end

  #Returns collection of photos associated with a place
  def photos(offset = 0, limit = nil)
    result = []
    photos = Photo.find_photos_for_place(@id).skip(offset)
    photos = photos.limit(limit) if !limit.nil?

    if photos.count
      photos.map do |photo|
        result << Photo.new(photo)
      end
    end

    return result
  end

  #Persisted method to check if object was saved
  def persisted?
    @id.nil?
  end
  
end
