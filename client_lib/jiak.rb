#!/usr/bin/env ruby
#     This file is provided to you under the Apache License,
#     Version 2.0 (the "License"); you may not use this file
#     except in compliance with the License.  You may obtain
#     a copy of the License at
   
#       http://www.apache.org/licenses/LICENSE-2.0
   
#     Unless required by applicable law or agreed to in writing,
#     software distributed under the License is distributed on an
#     "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#     KIND, either express or implied.  See the License for the
#     specific language governing permissions and limitations
#     under the License.    

# A Ruby interface for speaking to Riak.
# Example usage code can be found at the end of this file.
# This library requires that you have a library providing 'json'
# installed ("gem install json" will get you one).
require 'net/http'
require 'rubygems'
require 'json'

class JiakClient
  def initialize(ip, port, jiakPrefix='/jiak/', options={})
    @ip = ip
    @port = port
    @prefix = jiakPrefix
    @opts = options
  end

  # Set the schema for 'bucket'.  The schema parameter
  # must be a hash with at least an 'allowed_fields' field.
  # Other valid fields are 'requried_fields', 'read_mask',
  # and 'write_mask'
  def set_bucket_schema(bucket, schema)
    if (!schema['required_fields'])
      schema['required_fields'] = []
    end
    if (!schema['read_mask'])
      schema['read_mask'] = schema['allowed_fields']
    end
    if (!schema['write_mask'])
      schema['write_mask'] = schema['read_mask']
    end

    do_req(set_data(Net::HTTP::Put.new(path(bucket)),
                    {'schema'=>schema}),
           '204')
  end

  # Get the schema and key list for 'bucket'
  def list_bucket(bucket)
    do_req(Net::HTTP::Get.new(path(bucket)), '200')
  end
  
  # Get the object stored in 'bucket' at 'key'
  def fetch(bucket, key, r=nil)
    do_req(Net::HTTP::Get.new(path(bucket, key,
                                   {'r'=>(r||@opts['r'])})),
           '200')
  end

  # Store 'object' in Riak.  If the object has not defined
  # its 'key' field, a key will be chosen for it by the server.
  def store(object, w=nil, dw=nil, r=nil)
    q = {
      'returnbody'=>'true',
      'w'=>(w||@opts['w']),
      'dw'=>(dw||@opts['dw']),
      'r'=>(r||@opts['r'])
    }
    if (object['key'])
      req = Net::HTTP::Put.new(path(object['bucket'], object['key'], q))
      code = '200'
    else
      req = Net::HTTP::Post.new(path(object['bucket'], nil, q))
      code = '201'
    end

    do_req(set_data(req, object), code)
  end

  # Delete the data stored in 'bucket' at 'key'
  def delete(bucket, key, rw=nil)
    do_req(Net::HTTP::Delete.new(path(bucket, key,
                                      {'rw'=>(rw||@opts['rw'])})),
           '204')
  end

  # Follow links from the object stored in 'bucket' at 'key'
  # to other objects.  The 'spec' parameter should be an array
  # of hashes, each hash optinally defining 'bucket', 'tag',
  # and 'acc' fields.  If a field is not defined in a spec hash,
  # the wildcard '_' will be used instead.
  def walk(bucket, key, spec)
    do_req(Net::HTTP::Get.new(path(bucket, key)+convert_walk_spec(spec)),
           '200')
  end

  def convert_walk_spec(spec)
    acc = ''
    spec.each do |step|
      acc += URI.encode(step['bucket']||'_')+','+
        URI.encode(step['tag']||'_')+','+
        (step['acc']||'_')+'/'
    end
    acc
  end

  def path(bucket, key=nil, reqOpts={})
    p = @prefix + URI.encode(bucket) + '/'
    if (key)
      p += URI.encode(key) + '/'
    end

    q = [];
    reqOpts.each do |n,v|
      if (v): q.push "#{n}=#{v}" end
    end
    if (q.length > 0): p += '?'+(q.join('&')) end

    p
  end

  def set_data(req, data)
    req.content_type='application/json'
    req.body=JSON.generate(data)
    req
  end

  def do_req(req, expect)
    res = Net::HTTP.start(@ip, @port) {|http|
      http.request(req)
    }
    if (res.code == expect)
      res.body ? JSON.parse(res.body) : true
    else
      raise JiakException.new(res.code+' '+res.message+' '+res.body)
    end
  end
  private:convert_walk_spec
  private:path
  private:set_data
  private:do_req
end

class JiakException<Exception
 end

# Example usage
if __FILE__ == $0
  jc = JiakClient.new("127.0.0.1", 8000)

  puts "Creating bucket foo..."
  jc.set_bucket_schema('foo', {'allowed_fields'=>['bar','baz']})
  b = jc.list_bucket('foo')
  puts "Bucket foo's schema: "
  p b['schema']

  puts "Creating object..."
  o = jc.store({'bucket'=>'foo',
                 'object'=>{'bar'=>'hello'},
                 'links'=>[]})
  puts "Created at "+o['key']

  puts "Creating link..."
  jc.store({'bucket'=>'foo',
             'key'=>'my known key',
             'object'=>{'baz'=>'good'},
             'links'=>[['foo',o['key'],'tagged']]})
  puts "Following link..."
  objs = jc.walk('foo', 'my known key', [{'bucket'=>'foo'}])
  puts "Made it back to: "
  p objs['results'][0][0]

  puts "Modifying object..."
  mo = jc.fetch('foo', 'my known key')
  mo['object']['bar']=42
  jc.store(mo)
  puts "Stored."

  puts "Deleting foo/"+o['key']+"..."
  jc.delete('foo', o['key'])
  puts "Deleted."
end