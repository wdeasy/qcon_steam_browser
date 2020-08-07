class User < ApplicationRecord
  include Name
  require 'open-uri'

  belongs_to :host, -> {where(visible: true)}, counter_cache: true, optional: true
  belongs_to :seat, optional:true
  belongs_to :game, optional: true
  belongs_to :mod, optional: true
  has_many :api_keys
  has_many :identities, -> {where(enabled: true).where(banned: false)}
  #has_many :active_identities, -> {where(enabled: true)}, :class_name => 'Identity'
  #belongs_to :active_host, -> {where(visible: true)}, :class_name => 'Host'

  def as_json(options={})
   super(:only => [:clan, :handle], :methods => [:playing],
      :include => {
        :seat => {:only => [:seat, :section, :row, :number]},
        :host => {:only => [:url]},
        :identities => {:only => [:uid, :provider, :name, :url, :avatar]}
      }
    )
  end

  scope :active, -> { where( banned: false ) }

  def self.create_with_omniauth
    User.create
  end

  def self.update_with_omniauth(user_id, name)
    user = User.find_by(:id => user_id)
    if user.auto_update == true
      name = Name.clean_name(name)
      user.update_attributes(
        clan: set_clan(name, user.id, user.seat_id),
        handle: set_handle(name, user.id, user.seat_id)
      )
    end
  end

  def User.update(player, host_id, game_id, mod_id=nil)
    identity = Identity.find_by(:uid => player["steamid"], :provider => :steam)
    user = User.find_by(:id => identity.user_id)
    if identity.nil?
      puts "Could not find Identity for #{player["steamid"]}"
      return
    end

    if user.nil?
      puts "Could not find User for #{player["steamid"]}"
      return
    end

    if user.auto_update == true
      identity.update_attributes(
        :name => Name.clean_name(player["personaname"]),
        :url => Name.clean_url(player["profileurl"]),
        :avatar => player["avatar"]
      )
      user.update_attributes(
        :host_id => host_id,
        :game_id => game_id,
        :mod_id => mod_id,
        :clan => set_clan(player["personaname"], user.id, user.seat_id),
        :handle => set_handle(player["personaname"], user.id, user.seat_id),
        :updated => true
      )
    else
      user.update_attributes(
        :host_id => host_id,
        :updated => true
      )
    end
  end

  def User.url_cleanup(url)
    if url.include? "steamcommunity.com"
      unless url.start_with? "steamcommunity.com"
        url.slice!(0..(url.index('steamcommunity.com')-1))
      end

      url.prepend("https://")

      if url.last != "/"
        url << "/"
      end
    end
    return url
  end

  def User.steamid_from_url(url)
    begin
      url = url_cleanup(url)
      html = URI.open("#{url}?xml=1")
      doc = Nokogiri::XML(html)

      return doc.at_css("steamID64").text
    rescue => e
      return nil
    end
  end

  def User.search_summary_for_seat(steamid, seat)
    begin
      url = "https://steamcommunity.com/profiles/#{steamid}/"
      html = URI.open(url)
      doc = Nokogiri::HTML(html)

      if doc.css('div.profile_summary')
        if doc.css('div.profile_summary').text.include? seat
          return true
        else
          return "Could not find #{seat} in your steam profile summary."
        end
      else
        return "Please set your steam profile to public to link your seat."
      end
    rescue => e
      return "Unable to read your steam profile. Please try again."
    end
  end

  def User.update_seat_from_omniauth(user_id, seat_id)
    success = false
    message = ""

    user = User.find_by(id: user_id)
    if user.nil?
      message = "That user doesn't exist!"
      return {:success => success, :message => message}
    end

    # if seat_id.downcase.strip == 'none'
    #   success = user.update_attribute(:seat_id, nil)
    #   if success == true
    #     message = "You're unlinked from your seat!"
    #     return {:success => success, :message => message}
    #   else
    #     message = "Unable to save your seat."
    #     return {:success => success, :message => message}
    #   end
    # else
      seat = Seat.where(:seat => seat_id).first
      if seat.nil?
        message = "That seat doesn't exist!"
        return {:success => success, :message => message}
      end
    # end

    #just for 2020
    taken_seat = User.where(seat_id: seat.id).first
    if !taken_seat.nil? && taken_seat.id != user.id
      message = "That seat is taken!"
      return {:success => success, :message => message}
    end

    if seat == user.seat
      message = "You're linked to #{seat.seat}!"
      return {:success => true, :message => message}
    end

    if (user.banned == true )#|| (user.seat_count > 2 && user.admin == false))
      message = "You're linked to #{seat.seat}!"
      return {:success => true, :message => message}
    else
      success = user.update_attributes(
        :seat_id => seat.id,
        :seat_count => user.seat_count + 1
      )

      if success == true
        message = "You're linked to #{seat.seat}!"
        return {:success => success, :message => message}
      else
        message = "Unable to save your seat."
        return {:success => success, :message => message}
      end
    end
  end

  def User.update_seat(seat_id, url)
    success = false
    message = ""

    if seat_id.nil?
      message = "Please select a seat."
      return {:success => success, :message => message}
    end

    if url.nil?
      message = "Please enter your profile URL"
      return {:success => success, :message => message}
    end

    url = User.url_cleanup(url)
    unless url.start_with?('http://steamcommunity.com/id/','http://steamcommunity.com/profiles/','https://steamcommunity.com/id/','https://steamcommunity.com/profiles/')
      message "Please enter a valid profile URL"
      return {:success => success, :message => message}
    end

    steamid = User.steamid_from_url(url)
    if steamid.nil?
      message = "Could not parse steamid from URL. Please check the url and try again."
      return {:success => success, :message => message}
    end

    seat = Seat.where(:seat => seat_id).first
    if seat.nil?
      message = "Unknown seat."
      return {:success => success, :message => message}
    end

    response = search_summary_for_seat(steamid, seat.seat)
    if response == true
      user = User.lookup(steamid)

      #just for 2020
      taken_seat = User.where(seat_id: seat.id).first
      if !taken_seat.nil? && taken_seat.id != user.id
        message = "That seat is taken!"
        return {:success => success, :message => message}
      end

      if seat == user.seat
        message = "You're linked to #{seat.seat}!"
        return {:success => true, :message => message}
      end

      unless (user.banned == true)# || (user.seat_count > 2 && user.admin == false))
        user.update_attributes(
          :seat_id => seat.id,
          :seat_count => user.seat_count + 1
        )
        User.fill(steamid)
      end

      success = true
      message =  "You're linked to #{seat.seat}!"
      return {:success => success, :message => message}
    else
      message = response
      return {:success => success, :message => message}
    end
  end

  def User.lookup(steamid)
    identity = Identity.find_by(uid: steamid, provider: :steam)
    if identity.nil?
      identity = Identity.create(uid: steamid, provider: :steam, enabled: true)
    end

    if identity.user_id.nil?
      user = User.create
      identity.user = user
      identity.save
    end

    return identity.user
  end

  def User.fill(steamid)
    parsed = SteamWebApi.get_json(SteamWebApi.get_player_summaries + steamid)

    if parsed != nil
      parsed["response"]["players"].each do |player|
        User.update(player, nil, nil)
      end
    end
  end

  def User.set_clan(username, user_id, seat_id)
    h = Name.clean_name(username)
    if h.match(/^\[.*\S.*\].*\S.*$/)
      h.split(/[\[\]]/)[1].strip
    else
      nil
    end
  end

  def User.set_handle(username, user_id, seat_id)
    handle = Name.clean_name(username)
    handle = username.index('#').nil? ? username : username[0..(username.rindex('#')-1)]

    if handle.match(/^\[.*\S.*\].*\S.*$/)
      handle = handle.split(/[\[\]]/)[-1].strip
    end

    return handle
  end

  def display_handle
    if seat_id.nil?
      handle
    else
      prepend_seat(handle, id, seat_id)
    end
  end

  def prepend_seat(handle, user_id, seat_id)
    if seat_id.present?
      seat = User.find_by(:id => user_id).seat
      unless seat.nil?
        handle.prepend("[#{seat.seat}] ")
      end
    end
  end

  def url
    Identity.where(:user_id => id).specific(:steam).url
  end

  def playing
    if mod_id?
      mod.name
    elsif game_id?
      game.name
    else
      nil
    end
  end
end
