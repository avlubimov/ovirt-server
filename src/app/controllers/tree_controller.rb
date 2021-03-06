class TreeController < ApplicationController
  def get_pools
    # TODO: split these into separate hash elements for HW and smart pools
    pools = HardwarePool.get_default_pool.full_set_nested(:method => :json_hash_element,
                       :privilege => Privilege::VIEW, :user => get_login_user)
    pools += DirectoryPool.get_smart_root.full_set_nested(:method => :json_hash_element,
                       :privilege => Privilege::VIEW, :user => get_login_user,
                       :smart_pool_set => true)
  end

  def fetch_nav
    @pools = get_pools
  end

  def fetch_json
    render :json => get_pools.to_json
  end

  def return_filtered_list
    @ids = Array.new
    @clientHash = {}
    if (params[:item])
      params[:item].each { |item|
        tempItem = item.split("-",2)
        itemHash = {
          :id => tempItem[0].to_s,
          :name =>tempItem[1]
        }
        @clientHash[tempItem[0]] = itemHash
      }
    end
    pools = build_json(
                HardwarePool.get_default_pool.full_set_nested(
                    :method => :json_hash_element,
                    :privilege => Privilege::VIEW,
                    :user => get_login_user))
    smart_pools = adjust_smart_pool_list(
                      build_json(
                          DirectoryPool.get_smart_root.full_set_nested(
                              :method => :json_hash_element,
                              :privilege => Privilege::VIEW,
                              :user => get_login_user,
                              :smart_pool_set => true)))
    @serverHash = {:pools => smart_pools + pools }
    @ids.each { |item|
      if @clientHash.has_key?(item.to_s)
        @clientHash.delete(item.to_s)
      end
    }
    @serverHash[:deleted] = @clientHash
    render :json => @serverHash.to_json
  end

  private
  def build_json(list)
    list.each {|listItem|
      process_list_item(listItem)
      if listItem.has_key?(:children)
          build_json(listItem[:children])
      end
    }
    list
  end

  def process_list_item(item)
    if @clientHash.has_key?(item[:id].to_s)
      unless @clientHash[item[:id].to_s][:name] == item[:name]
        item[:state] = "changed"
      else
        item[:state] = "unchanged"
      end
    else
      item[:state] = "new"
    end
    @ids = @ids.push(item[:id])
  end

  def adjust_smart_pool_list(list)
    # list should have a single element. If it doesn't, don't transform anything here
    if list.size == 1
      smart_root = list[0]
      smart_root[:name] = "Smart Pools"
      smart_root[:type] = "SmartPoolRoot"
      smart_root[:state] = "unchanged"
      mySmartPools = Array.new
      otherSmartPools = Array.new
      if smart_root.has_key?(:children)
        smart_root[:children].each do |listItem|
          if (listItem[:name] == get_login_user)
            if listItem.has_key?(:children)
              listItem[:children].each {|item|
                item[:parent_id] = smart_root[:id]
                mySmartPools.push(item)
              }
            end
          else
            otherSmartPools.push(listItem) if listItem.has_key?(:children)
          end
        end
        smart_root[:children] = mySmartPools + otherSmartPools
      end
    end
    list
  end
end
