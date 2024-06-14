var __old_drawMap = $.stonehearth.stonehearthMap.prototype._drawMap;

$.stonehearth.stonehearthMap.prototype._drawMap = function(context) {
   var self = this;
   radiant.call('fortuna_romanorum:custom_biome_type_heights')
      .always(function(response) {
         self.typeHeights = response.typeHeights;
         return __old_drawMap.call(self, context)
      })
}
