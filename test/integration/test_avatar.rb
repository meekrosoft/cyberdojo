    super
    kata = make_kata(@dojo, 'Ruby-TestUnit')
    kata = make_kata(@dojo, 'Ruby-TestUnit')
    diff = avatar.tags[1].diff(2)
    added_line =
    {
      :type   => :added,
      :line   => 'xxxx',
      :number => 3
    }
    assert diff['cyber-dojo.sh'].include?(added_line), diff.inspect
    kata = make_kata(@dojo, 'Ruby-TestUnit')
    diff = avatar.tags[0].diff(1)
    added =
    [
       { :type=>:section, :index=>0
       },
       { :type   => :added,
         :line   => content,
         :number => 1
       }
    ]
    assert_equal added, diff[added_filename]
    kata = make_kata(@dojo, 'Ruby-TestUnit')
    diff = avatar.tags[1].diff(2)
    deleted =
    [
      {
        :line   => content,
        :type   => :deleted,
        :number => 1
      }
    ]
    assert_equal deleted, diff[deleted_filename], diff.inspect
    kata = make_kata(@dojo, 'Ruby-TestUnit')