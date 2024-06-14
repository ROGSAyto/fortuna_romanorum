App.StonehearthSLImmigrationReportDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'SLImmigrationReportBulletinDialog',

   _updateFactions: function () {
      var self = this;
      self.set(
        'factions',
        radiant.map_to_array(
            self.get('model.data.factions'),
            function (faction_id, faction_data) {
               faction_data.faction_id = faction_id;
               return faction_data;
            }
        ).sort(function (l, r) {
           return l['ordinal'] - r['ordinal'];
        }
              )
       );
   }.observes('model.data.factions'),

   init: function() {
      this._super();
      this.hasPlayedConclusionJingle = false;
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      this.passOrFailElement('food_data', this.$('#SLImmigrationReportBulletinDialog #foodBlock'), 500 );
      this.passOrFailElement('net_worth_data', this.$('#SLImmigrationReportBulletinDialog #netWorthBlock'), 1500 );

    // add tooltip
      self.$('#foodImageDiv').tooltipster({content: i18n.t('stonehearth:ui.game.bulletin.immigration_report.tooltips.food')});
      self.$('#netWorthImageDiv').tooltipster({content: i18n.t('stonehearth:ui.game.bulletin.immigration_report.tooltips.net_worth')});
      self.$('#populationIcon').tooltipster({content: i18n.t('stonehearth:ui.game.citizens.title')});
      // self.$('#moraleIcon').tooltipster({content: i18n.t('stonehearth:ui.game.bulletin.immigration_report.tooltips.morale')});

      //Add a last beat for the conclusion
      setTimeout(function() {
         if (self.destroyed) {
            return;
         }
         self.$('#SLImmigrationReportBulletinDialog #conclusionDiv').css('visibility', 'visible');
         self.$('#SLImmigrationReportBulletinDialog #conclusionDiv').pulse();

         self.$('#SLImmigrationReportBulletinDialog #factionSectionDiv').css('display', 'flex');

         self._playConclusionJingle();
      }, 3500);

      self.dialog.on('click', '.factionButton', function() {
         var bulletin = self.get('model');
         var instance = bulletin.callback_instance;
         var method = bulletin.data['accepted_callback'];
         radiant.call_obj(instance, method, $(this).attr('data-faction-id'))
            .done(function () {
               self._playConclusionJingle();
               self._autoDestroy();
            })
      });
      this.$('#okButton').click(function() {
         self._playConclusionJingle();
      });

      // set morale status images and bar
      self._scoreTrace = new StonehearthDataTrace(App.stonehearthClient.gameState.scoresUri, {})
         .progress(function(eobj) {
            self.set('score_data', eobj);
            var score = eobj.median.happiness;
            var moodNumber = Math.round(score);
            var moodIcon = '';
            $.each(App.happinessConstants.mood_data, function(mood, data) {
               if (data.score == moodNumber) { // found matching mood
                  self.set('morale_icon_style', 'background-image: url(' + data.icon + ')');
                  // Set the tooltip for the bar
                  var tooltipString = App.tooltipHelper.getTooltip(mood, null, true); // True for town description.
                  var moraleIcon = self.$('#moraleIcon');
                  if (tooltipString && moraleIcon && moraleIcon.data('tooltipster')) {
                     moraleIcon.tooltipster({
                        content: $(tooltipString)
                     });
                  }
                  return false; // break from each loop
               }
            });

            // Clean up the score trace, since we shouldn't update after we've already checked whether or not it passed
            if (self._scoreTrace) {
               self._scoreTrace.destroy();
               self._scoreTrace = null;
            }
         });
   },

   willDestroyElement: function() {
      var self = this;
      var imageDivs = ['foodImageDiv', 'netWorthImageDiv'];
      radiant.each(imageDivs, function(i, div) {
         self.$('#' + div).tooltipster('destroy');
      });
      this._super();
   },

   _playConclusionJingle: function() {
      var self = this;
      if (self.hasPlayedConclusionJingle) {
         return;
      }
      self.hasPlayedConclusionJingle = true;
      if (self.get('model.data.accepted_callback')) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:immigration_menu:immigration_positive'} );
      } else {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:immigration_menu:immigration_negative'} );
      }
   },

   passOrFailElement: function (elementName, $targetBlock, delay) {
      var self = this;
      setTimeout( function() {
         if (self.destroyed) {
            return;
         }
         var targetString = 'model.data.message.' + elementName;
         var $targetElement = $targetBlock.find('.statusDiv');
         var $possessedSpan = $targetBlock.find('.possessedSpan')

         $targetElement.css('visibility', 'visible');

         if (self.get(targetString + '.success')) {
            $targetElement.removeClass("failed");
            $targetElement.addClass("passed");
            $possessedSpan.removeClass("failedText");
            $possessedSpan.addClass("successText");
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:immigration_menu:immigration_pass'} );

         } else {
            $targetElement.removeClass("passed");
            $targetElement.addClass("failed");
            $possessedSpan.removeClass("successText");
            $possessedSpan.addClass("failedText");
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:immigration_menu:immigration_fail'} );
         }
         $targetElement.pulse();

         //TODO for DougP: pick some other sound? Whatever you like!
      }, delay);
   },

   destroy: function() {
      if (this._scoreTrace) {
         this._scoreTrace.destroy();
         this._scoreTrace = null;
      }
      this.destroyed = true;
      this._super();
   }

});

App.StonehearthSLImmigrationRosterEntryView = App.View.extend({
   tagName: 'div',
   classNames: ['rosterEntry'],
   templateName: 'SLImmigrationRosterEntry',
   uriProperty: 'model',

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:attributes': {},
      'stonehearth:traits' : {
         'traits': {
            '*' : {}
         }
      },
      'render_info': {}
   },

   init: function() {
      this._portraitId = 0;
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self._update();
      Ember.run.scheduleOnce('afterRender', self, '_updateStatTooltips');
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      if (this._nameInput) {
         this._nameInput.destroy();
         this._nameInput = null;
      }
      this._super();
   },

   _updatePortrait: function() {
      var self = this;
      // add a dummy parameter portraitId so ember will rerender the portrait even if the entity stays the same (their appearance may have changed)
      self.set('portrait', '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + self._citizenObjectId + '&portraitId=' + self._portraitId);
      self._portraitId += 1;
   },

   _updateStatTooltips: function() {
      var self = this;

      self.$('.stat').each(function(){
         var attrib_name = $(this).attr('id');
         var tooltipString = App.tooltipHelper.getTooltip(attrib_name);
         $(this).tooltipster({content: $(tooltipString)});
      });
   },

   _onNameChanged: function() {
      var unit_name = i18n.t(this.get('model.stonehearth:unit_info.display_name'), {self: this.get('model')});
      this.set('model.unit_name', unit_name);
   }.observes('model.stonehearth:unit_info'),


   _update: function() {
      var self = this;
      var citizenData = self.get('model');
      if (self.$() && citizenData) {
         self._citizenObjectId = citizenData.__self;
         self._updateCitizenView(self._citizenObjectId);
      }
   }.observes('model'),

   _updateCitizenView: function(citizen) {
      var self = this;

      if (citizen) {
         self._updatePortrait();
      }
   },

   _buildTraitsArray: function() {
      var traits = [];
      var traitMap = this.get('model.stonehearth:traits.traits');

      if (traitMap) {
         traits = radiant.map_to_array(traitMap);
         traits.sort(function(a, b){
            var aUri = a.uri;
            var bUri = b.uri;
            var n = aUri.localeCompare(bUri);
            return n;
         });
      }

      this.set('traits', traits);
   }.observes('model.stonehearth:traits')
});