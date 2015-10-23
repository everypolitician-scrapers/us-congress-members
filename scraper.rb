#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'pry'
require 'yaml'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

require 'csv'
termdates = <<EODATA
id,name,start_date,end_date,wikidata
114,114th Congress,2015-01-06,2017-01-03,Q16146771
113,113th Congress,2013-01-06,2015-01-03,Q71871
112,112th Congress,2011-01-06,2013-01-03,Q170447
111,111th Congress,2009-01-06,2011-01-03,Q170375
110,110th Congress,2007-01-06,2009-01-03,Q170018
109,109th Congress,2005-01-06,2007-01-03,Q168778
108,108th Congress,2003-01-06,2005-01-03,Q168504
107,107th Congress,2001-01-06,2003-01-03,Q2057259
106,106th Congress,1999-01-06,2001-01-03,Q3596897
105,105th Congress,1997-01-06,1999-01-03,Q3596884
104,104th Congress,1995-01-06,1997-01-03,Q3596857
103,103rd Congress,1993-01-06,1995-01-03,Q3556780
102,102nd Congress,1991-01-06,1993-01-03,Q347346
101,101st Congress,1989-01-06,1991-01-03,Q4546373
100,100th Congress,1987-01-06,1989-01-03,Q4546248
99,99th Congress,1985-01-06,1987-01-03,Q4646349
98,98th Congress,1983-01-06,1983-01-03,Q4646254
97,97th Congress,1981-01-06,1983-01-03,Q4646187
96,96th Congress,1979-01-06,1981-01-03,Q4646121
95,95th Congress,1977-01-06,1979-01-03,Q4646042
EODATA
@congress = CSV.parse(termdates, headers: true, header_converters: :symbol).map(&:to_hash)

def overlap(mem, congress)
  mS = mem['start'].to_s.empty?  ? '0000-00-00' : mem['start']
  mE = mem['end'].to_s.empty?    ? '9999-12-31' : mem['end']
  tS = congress[:start_date].to_s.empty? ? '0000-00-00' : congress[:start_date]
  tE = congress[:end_date].to_s.empty?   ? '9999-12-31' : congress[:end_date]

  return unless mS <= tE && mE >= tS
  (s, e) = [mS, mE, tS, tE].sort[1,2]
  return { 
    start_date: s == '0000-00-00' ? nil : s,
    end_date:   e == '9999-12-31' ? nil : e,
  }
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
  if data[:district].to_i.zero?
    return "ocd-division/country:us/state:%s" % data[:state].downcase 
  else
    return "ocd-division/country:us/state:%s/cd:%s" % [ data[:state].downcase, data[:district] ]
  end
end

# https://github.com/unitedstates/congress-legislators/blob/master/scripts/everypolitician.py
def name_from(names)
  return names['official_full'] if names.key? 'official_full'

  first = names['first']
  first = names['middle']   if first.end_with?('.') and names.key?('middle')
  first = names['nickname'] if names.key?('nickname') and names['nickname'].length < first.length

  last = names['last']
  last = "%s, %s" % [names['last'], names['suffix']] if names.key? 'suffix'

  name = first + ' ' + last  
  raise "No name for #{names}" if name.to_s.empty?
  return name
end

def scrape_list(url)
  yaml_at(url).each do |person|
    terms = person['terms'].find_all { |t| t['start'] >= '1977-01-01' }
    next if terms.empty?

    person_data = { 
      id: person['id']['bioguide'],
      name: name_from(person['name']),
      image: "https://theunitedstates.io/images/congress/original/#{person['id']['bioguide']}.jpg",
      given_name: person['name']['first'],
      family_name: person['name']['last'],
      sort_name: "%s, %s" % [ person['name']['last'], person['name']['first'] ],
      birth_date: person['bio']['birthday'],
      gender: gender_from(person['bio']['gender']),
    }
    person['id'].each { |k,v| person_data["identifier__#{k}".to_sym] = [v].flatten.first }  

    terms.each do |term|
      tdata = { 
        house: term['type'],
        start_date: term['start'],
        state: term['state'],
        district: term['district'],
        party: term['party'],
        homepage: term['url'],
        address: term['address'],
        phone: term['phone'],
        fax: term['fax'],
      }
      tdata[:area_id] = area_from(tdata)
      alldata = person_data.merge(tdata)

      @congress.find_all { |c| c[:start_date] <= term['end'] && c[:end_date] >= term['start'] }.each do |c|
        next unless c[:id].to_i >= 97  
        o = overlap(term, c)
        data = alldata.merge({ 
          term: c[:id],
          start_date: o[:start_date],
          end_date: o[:end_date],
        })
        next if data[:start_date] == data[:end_date]
        # puts "%s %s %s (%s - %s)" % [data[:term], data[:house], data[:name], data[:start_date], data[:end_date]]
        ScraperWiki.save_sqlite([:id, :term], data)
      end
    end

  end
end

scrape_list('https://raw.githubusercontent.com/unitedstates/congress-legislators/master/legislators-current.yaml')
scrape_list('https://raw.githubusercontent.com/unitedstates/congress-legislators/master/legislators-historical.yaml')
