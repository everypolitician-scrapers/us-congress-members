#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'yaml'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def yaml_at(url)
  YAML.load(open(url).read)
end

def gender_from(str)
  return if str.empty?
  return 'male' if str.downcase == 'm'
  return 'female' if str.downcase == 'f'
  raise "unknown gender: #{str}"
end

def area_from(data)
  raise "No state for #{data}" if data[:state].to_s.empty?
  if data[:house] == 'sen'
    return "ocd-division/country:us/state:%s" % data[:state].downcase 
  else
    raise "No district for #{data}" if data[:district].to_s.empty?
    return "ocd-division/country:us/state:%s/cd:%s" % [ data[:state].downcase, data[:district] ]
  end
end


def scrape_list(url)
  yaml_at(url).each do |person|
    # TODO any in current Term
    term = person['terms'].last
    data = { 
      id: person['id']['bioguide'],
      wikipedia__en: person['id']['wikipedia'],
      name: person['name']['official_full'],
      image: "https://theunitedstates.io/images/congress/original/#{person['id']['bioguide']}.jpg",
      given_name: person['name']['first'],
      family_name: person['name']['last'],
      sort_name: "%s, %s" % [ person['name']['last'], person['name']['first'] ],
      birth_date: person['bio']['birthday'],
      gender: gender_from(person['bio']['gender']),
      house: term['type'],
      start_date: term['start'],
      state: term['state'],
      district: term['district'],
      party: term['party'],
      homepage: term['url'],
      address: term['address'],
      phone: term['phone'],
      fax: term['fax'],
      term: 114,
    }
    data[:area_id] = area_from(data)
    ScraperWiki.save_sqlite([:id], data)
  end
end

scrape_list('https://raw.githubusercontent.com/unitedstates/congress-legislators/master/legislators-current.yaml')
